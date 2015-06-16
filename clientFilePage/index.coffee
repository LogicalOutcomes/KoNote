# UI logic for the client file window.
#
# Most of the state for this page is held in a `clientFile` object.  Various
# fields in this object are "transient", meaning that they are not saved when
# the application is closed.  Typically, these track things like what field is
# currently selected.  The function `toSavedFormat` is used to remove these
# transient fields before saving, while `fromSavedFormat` initialize them with
# some default values.
#
# The client file is automatically saved to disk every time a non-transient
# field is changed in ClientPage.state.clientFile.

# Libraries from Node.js context
_ = require 'underscore'
Async = require 'async'
Imm = require 'immutable'
Moment = require 'moment'

Config = require '../config'
Persist = require '../persist'

load = (win, {clientFileId}) ->
	# Libraries from browser context
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM
	Gui = win.require 'nw.gui'
	CrashHandler = require('../crashHandler').load(win)
	Spinner = require('../spinner').load(win)
	BrandWidget = require('../brandWidget').load(win)
	PlanTab = require('./planTab').load(win)
	ProgNotesTab = require('./progNotesTab').load(win)
	AnalysisTab = require('./analysisTab').load(win)
	{FaIcon, renderName, showWhen, stripMetadata} = require('../utils').load(win)

	nwWin = Gui.Window.get(win)

	DataStore = do ->
		clientFile = null
		clientFileLock = null
		progressNotes = null
		planTargetsById = Imm.Map()
		metricsById = Imm.Map()
		startupTasks = Imm.Set() # set of task IDs
		ongoingTasks = Imm.Set() # set of task IDs
		isClosed = false
		loadErrorType = null

		init = ->
			render()
			loadData()
			registerListeners()

		process.nextTick init

		# Render (or re-render) the page
		render = ->
			React.render new ClientPage({
				# Data stores
				clientFile
				progressNotes
				planTargetsById
				metricsById
				startupTasks
				ongoingTasks
				loadErrorType

				# Data store methods
				registerTask
				unregisterTask
				loadData
				updateClientFile
				unregisterListeners
			}), $('#container')[0]

		registerTask = (taskId, isStartupTask) ->
			if ongoingTasks.contains taskId
				throw new Error "duplicate task with ID #{JSON.stringify taskId}"

			if startupTasks.contains taskId
				throw new Error "duplicate task with ID #{JSON.stringify taskId}"

			ongoingTasks = ongoingTasks.add(taskId)

			if isStartupTask
				startupTasks = startupTasks.add(taskId) 
				console.log "Started #{taskId} (startup)"
			else
				console.log "Started #{taskId}"

			render()

		unregisterTask = (taskId, isStartupTask) ->
			unless ongoingTasks.contains taskId
				throw new Error "unknown task ID #{JSON.stringify taskId}"

			if isStartupTask and not startupTasks.contains taskId
				throw new Error "unknown startup task ID #{JSON.stringify taskId}"

			ongoingTasks = ongoingTasks.delete(taskId)

			if isStartupTask
				startupTasks = startupTasks.delete(taskId)
				console.log "Finished #{taskId} (startup)"
			else
				console.log "Finished #{taskId}"

			render()

		loadData = ->
			planTargetHeaders = null
			progNoteHeaders = null
			metricHeaders = null

			registerTask 'initialDataLoad', true
			Async.series [
				(cb) ->
					# TODO data dir
					Persist.Lock.acquire 'data', "clientFile-#{clientFileId}", (err, result) ->
						if err
							if err instanceof Persist.Lock.LockInUseError
								loadErrorType = 'file-in-use'
								render()
								return

							cb err
							return

						clientFileLock = result
						cb()
				(cb) ->
					ActiveSession.persist.clientFiles.readLatestRevisions clientFileId, 1, (err, revisions) =>
						if err
							cb err
							return

						clientFile = stripMetadata revisions.get(0)
						cb()
				(cb) ->
					ActiveSession.persist.planTargets.list clientFileId, (err, results) =>
						if err
							cb err
							return

						planTargetHeaders = results
						cb()
				(cb) ->
					Async.map planTargetHeaders.toArray(), (planTargetHeader, cb) ->
						ActiveSession.persist.planTargets.readRevisions clientFileId, planTargetHeader.get('id'), cb
					, (err, results) ->
						if err
							cb err
							return

						planTargetsById = Imm.List(results)
						.map (planTargetRevs) ->
							id = planTargetRevs.getIn([0, 'id'])
							return [
								id
								Imm.Map({id, revisions: planTargetRevs.reverse()})
							]
						.fromEntrySeq().toMap()

						cb()
				(cb) ->
					ActiveSession.persist.progNotes.list clientFileId, (err, results) =>
						if err
							cb err
							return

						progNoteHeaders = results
						cb()
				(cb) ->
					Async.map progNoteHeaders.toArray(), (progNoteHeader, cb) ->
						ActiveSession.persist.progNotes.read clientFileId, progNoteHeader.get('id'), cb
					, (err, results) ->
						if err
							cb err
							return

						progressNotes = Imm.List(results)
						cb()
				(cb) ->
					ActiveSession.persist.metrics.list (err, results) ->
						if err
							cb err
							return

						metricHeaders = results
						cb()
				(cb) ->
					Async.map metricHeaders.toArray(), (metricHeader, cb) ->
						ActiveSession.persist.metrics.read metricHeader.get('id'), cb
					, (err, results) ->
						if err
							cb err
							return

						metricsById = Imm.List(results)
						.map (metric) ->
							return [metric.get('id'), metric]
						.fromEntrySeq().toMap()

						cb()
			], (err) ->
				if err
					if err instanceof IOError
						loadErrorType = 'io-error'
						render()
						return

					CrashHandler.handle err
					return

				# OK, all done
				unregisterTask 'initialDataLoad', true

		updateClientFile = (context, newValue) ->
			oldClientFile = clientFile
			clientFile = clientFile.setIn context, newValue

			# If there were no changes
			if Imm.is(clientFile, oldClientFile)
				return

			registerTask "updateClientFile"
			ActiveSession.persist.clientFiles.createRevision clientFile, (err) =>
				unregisterTask "updateClientFile"

				if err
					CrashHandler.handle err
					return

				console.log "Client file update successful."

				# Add a delay so that the user knows it saved
				slowSaveTaskId = "slow-save-#{Persist.generateId()}"
				registerTask slowSaveTaskId
				setTimeout unregisterTask.bind(null, slowSaveTaskId), 500

		registerListeners = ->
			global.ActiveSession.persist.eventBus.on 'create:planTarget createRevision:planTarget', (newRev) ->
				if isClosed
					return

				unless newRev.get('clientFileId') is clientFileId
					return

				targetId = newRev.get('id')

				if planTargetsById.has targetId
					planTargetsById = planTargetsById.updateIn [targetId, 'revisions'], (revs) ->
						return revs.unshift newRev
				else
					planTargetsById = planTargetsById.set targetId, Imm.fromJS {
						id: targetId
						revisions: [newRev]
					}

				render()

			global.ActiveSession.persist.eventBus.on 'create:progNote', (newProgNote) ->
				if isClosed
					return

				unless newProgNote.get('clientFileId') is clientFileId
					return

				progressNotes = progressNotes.push newProgNote

				render()

			global.ActiveSession.persist.eventBus.on 'create:metric', (newMetric) ->
				if isClosed
					return

				metricsById = metricsById.set newMetric.get('id'), newMetric

				render()

		unregisterListeners = ->
			isClosed = true

			if clientFileLock
				clientFileLock.release()

		return {}

	ClientPage = React.createFactory React.createClass
		getInitialState: ->
			return {
				activeTabId: 'plan'
			}

		componentWillMount: ->
			nwWin.maximize()			

			nwWin.on 'close', (event) =>				

				# # If page still loading
				# # TODO handle this more elegantly
				unless @props.clientFile?
					@props.unregisterListeners()
					nwWin.close true
					return

				clientName = renderName @props.clientFile.get('clientName')

				if @refs.planTab.hasChanges()
					Bootbox.dialog {
						title: "Unsaved Changes to Plan"
						message: "You have unsaved changes in this plan for #{clientName}. How would you like to proceed?"
						buttons: {
							default: {
								label: "Cancel"
								className: "btn-default"
								callback: => Bootbox.hideAll()
							}
							danger: {
								label: "Discard Changes"
								className: "btn-danger"
								callback: => 
									@props.unregisterListeners()
									nwWin.close true
							}
							success: {
								label: "View Plan"
								className: "btn-success"
								callback: => 
									Bootbox.hideAll()
									@setState {activeTabId: 'plan'}, @refs.planTab.blinkUnsaved
							}
						}
					}
				else
					@props.unregisterListeners()
					nwWin.close(true)

		render: ->
			if @props.loadErrorType
				return LoadError {loadErrorType: @props.loadErrorType}

			else if @props.startupTasks.size > 0 or not @props.clientFile
				return R.div({className: 'clientFilePage'},
					Spinner({isOverlay: true, isVisible: true})
				)

			activeTabId = @state.activeTabId

			clientName = renderName @props.clientFile.get('clientName')
			recordId = @props.clientFile.get('recordId')
			nwWin.title = "#{clientName} - KoNote"

			return R.div({className: 'clientFilePage'},
				Spinner({isOverlay: true, isVisible: @props.ongoingTasks.size > 0})
				Sidebar({
					clientName
					recordId
					activeTabId
					onTabChange: @_changeTab
				})
				PlanTab.PlanView({
					ref: 'planTab'
					isVisible: activeTabId is 'plan'
					clientFileId
					plan: @props.clientFile.get('plan')
					planTargetsById: @props.planTargetsById
					metricsById: @props.metricsById
					registerTask: @props.registerTask
					unregisterTask: @props.unregisterTask
					updatePlan: @props.updateClientFile.bind null, ['plan']
				})
				ProgNotesTab.ProgNotesView({
					isVisible: activeTabId is 'progressNotes'
					clientFileId
					progNotes: @props.progressNotes
					metricsById: @props.metricsById
					registerTask: @props.registerTask
					unregisterTask: @props.unregisterTask
				})
				AnalysisTab.AnalysisView({
					isVisible: activeTabId is 'analysis'
					clientFileId
					progNotes: @props.progressNotes
					metricsById: @props.metricsById
					registerTask: @props.registerTask
					unregisterTask: @props.unregisterTask
				})
			)
		_changeTab: (newTabId) ->
			@setState {
				activeTabId: newTabId
			}

	Sidebar = React.createFactory React.createClass
		render: ->
			activeTabId = @props.activeTabId

			return R.div({className: 'sidebar'},
				R.img({src: 'customer-logo-sm.png'}),
				R.div({className: 'logoSubtitle'},
					Config.logoSubtitle
				)
				R.div({className: 'clientName'},
					R.span({}, "#{@props.clientName}")
				)
				R.div({className: 'recordId'},
					R.span({}, if @props.recordId and @props.recordId.length > 0 then "ID# #{@props.recordId}")
				),
				R.div({className: 'tabStrip'},
					SidebarTab({
						name: "Plan"
						icon: 'sitemap'
						isActive: activeTabId is 'plan'
						onClick: @props.onTabChange.bind null, 'plan'
					})
					SidebarTab({
						name: "Progress Notes"
						icon: 'pencil-square-o'
						isActive: activeTabId is 'progressNotes'
						onClick: @props.onTabChange.bind null, 'progressNotes'
					})
					SidebarTab({
						name: "Analysis"
						icon: 'line-chart'
						isActive: activeTabId is 'analysis'
						onClick: @props.onTabChange.bind null, 'analysis'
					})
				)				
				BrandWidget()
			)

	SidebarTab = React.createFactory React.createClass
		render: ->
			return R.div({
				className: "tab #{if @props.isActive then 'active' else ''}"
				onClick: @props.onClick
			},
				FaIcon @props.icon
				' '
				@props.name
			)

	LoadError = React.createFactory React.createClass
		componentDidMount: ->
			console.log "loadErrorType:", @props.loadErrorType
			msg = switch @props.loadErrorType
				when 'file-in-use'
					"This client file is already in use."
				when 'io-error'
					"""
						An error occurred while loading the client file. 
						This may be due to a problem with your network connection.
					"""
				else
					"An unknown error occured (loadErrorType: #{@props.loadErrorType}"				
			Bootbox.alert msg, -> nwWin.close(true)
		render: ->
			return R.div({className: 'clientFilePage'})

module.exports = {load}
