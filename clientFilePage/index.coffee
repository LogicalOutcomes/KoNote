# UI logic for the client file window.
#
# Most of the state for this page is held in a `clientFile` object.  Various
# fields in this object are "transient", meaning that they are not saved when
# the application is closed.  Typically, these track things like what field is
# currently selected.  The function `toSavedFormat` is used to remove these
# transient fields before saving, while `fromSavedFormat` initialize them with
# some default values.

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
	{registerTimeoutListeners, unregisterTimeoutListeners} = require('../timeoutDialog').load(win)
	{FaIcon, renderName, renderFileId, showWhen, stripMetadata} = require('../utils').load(win)

	nwWin = Gui.Window.get(win)

	process.nextTick =>
		React.render new ClientFilePage(), $('#container')[0]

	ClientFilePage = React.createFactory React.createClass
		getInitialState: ->
			return {
				clientFile: null
				clientFileLock: null
				progressNotes: null
				planTargetsById: Imm.Map()
				metricsById: Imm.Map()
				loadErrorType: null

				# TODO make these unnecessary:
				isClosed: false
				startupTasks: Imm.Set() # set of task IDs
				ongoingTasks: Imm.Set() # set of task IDs
			}

		componentDidMount: ->
			@_loadData()
			@_registerListeners()

		render: ->
			return new ClientFilePageUi({
				# Data stores
				clientFile: @state.clientFile
				progressNotes: @state.progressNotes
				planTargetsById: @state.planTargetsById
				metricsById: @state.metricsById
				startupTasks: @state.startupTasks
				ongoingTasks: @state.ongoingTasks
				loadErrorType: @state.loadErrorType

				# Data store methods
				updatePlan: @_updatePlan

				# TODO make these unnecessary:
				registerTask: @_registerTask
				unregisterTask: @_unregisterTask
				unregisterListeners: @_unregisterListeners
			})

		_registerTask: (taskId, isStartupTask) ->
			@setState (state) =>
				if state.ongoingTasks.contains taskId
					throw new Error "duplicate task with ID #{JSON.stringify taskId}"

				if state.startupTasks.contains taskId
					throw new Error "duplicate task with ID #{JSON.stringify taskId}"

				return {
					ongoingTasks: state.ongoingTasks.add(taskId)
					startupTasks: (if isStartupTask
						state.startupTasks.add(taskId)
					else
						state.startupTasks
					)
				}

		_unregisterTask: (taskId, isStartupTask) ->
			@setState (state) =>
				unless state.ongoingTasks.contains taskId
					throw new Error "unknown task ID #{JSON.stringify taskId}"

				if isStartupTask and not state.startupTasks.contains taskId
					throw new Error "unknown startup task ID #{JSON.stringify taskId}"

				return {
					ongoingTasks: state.ongoingTasks.delete(taskId)
					startupTasks: (if isStartupTask
						state.startupTasks.delete(taskId)
					else
						state.startupTasks
					)
				}

		_loadData: ->
			planTargetHeaders = null
			progNoteHeaders = null
			metricHeaders = null

			@_registerTask 'initialDataLoad', true
			Async.series [
				(cb) =>
					# TODO data dir
					Persist.Lock.acquire 'data', "clientFile-#{clientFileId}", (err, result) =>
						if err
							if err instanceof Persist.Lock.LockInUseError
								@setState {loadErrorType: 'file-in-use'}
								return

							cb err
							return

						@setState {
							clientFileLock: result
						}, cb
				(cb) =>
					ActiveSession.persist.clientFiles.readLatestRevisions clientFileId, 1, (err, revisions) =>
						if err
							cb err
							return

						@setState {
							clientFile: stripMetadata revisions.get(0)
						}, cb
				(cb) =>
					ActiveSession.persist.planTargets.list clientFileId, (err, results) =>
						if err
							cb err
							return

						planTargetHeaders = results
						cb()
				(cb) =>
					Async.map planTargetHeaders.toArray(), (planTargetHeader, cb) =>
						targetId = planTargetHeader.get('id')
						ActiveSession.persist.planTargets.readRevisions clientFileId, targetId, cb
					, (err, results) =>
						if err
							cb err
							return

						@setState {
							planTargetsById: Imm.List(results)
							.map (planTargetRevs) =>
								id = planTargetRevs.getIn([0, 'id'])
								return [
									id
									Imm.Map({id, revisions: planTargetRevs.reverse()})
								]
							.fromEntrySeq().toMap()
						}, cb
				(cb) =>
					ActiveSession.persist.progNotes.list clientFileId, (err, results) =>
						if err
							cb err
							return

						progNoteHeaders = results
						cb()
				(cb) =>
					Async.map progNoteHeaders.toArray(), (progNoteHeader, cb) =>
						ActiveSession.persist.progNotes.read clientFileId, progNoteHeader.get('id'), cb
					, (err, results) =>
						if err
							cb err
							return

						@setState {
							progressNotes: Imm.List(results)
						}, cb
				(cb) =>
					ActiveSession.persist.metrics.list (err, results) =>
						if err
							cb err
							return

						metricHeaders = results
						cb()
				(cb) =>
					Async.map metricHeaders.toArray(), (metricHeader, cb) =>
						ActiveSession.persist.metrics.read metricHeader.get('id'), cb
					, (err, results) =>
						if err
							cb err
							return

						@setState {
							metricsById: Imm.List(results)
							.map (metric) =>
								return [metric.get('id'), metric]
							.fromEntrySeq().toMap()
						}, cb
			], (err) =>
				if err
					if err instanceof Persist.IOError
						@setState {loadErrorType: 'io-error'}
						return

					CrashHandler.handle err
					return

				# OK, all done
				@_unregisterTask 'initialDataLoad', true

		_updatePlan: (plan, newPlanTargets, updatedPlanTargets) ->
			@_registerTask 'updatePlan'

			idMap = Imm.Map()

			Async.series [
				(cb) =>
					Async.each newPlanTargets.toArray(), (newPlanTarget, cb) =>
						transientId = newPlanTarget.get('id')
						newPlanTarget = newPlanTarget.delete('id')

						ActiveSession.persist.planTargets.create newPlanTarget, (err, result) =>
							if err
								cb err
								return

							persistentId = result.get('id')
							idMap = idMap.set(transientId, persistentId)
							cb()
					, cb
				(cb) =>
					Async.each updatedPlanTargets.toArray(), (updatedPlanTarget, cb) =>
						ActiveSession.persist.planTargets.createRevision updatedPlanTarget, cb
					, cb
				(cb) =>
					# Replace transient IDs with newly created persistent IDs
					newPlan = plan.update 'sections', (sections) =>
						return sections.map (section) =>
							return section.update 'targetIds', (targetIds) =>
								return targetIds.map (targetId) =>
									return idMap.get(targetId, targetId)
					newClientFile = @state.clientFile.set 'plan', newPlan

					# If no changes, skip this step
					if Imm.is(newClientFile, @state.clientFile)
						cb()
						return

					ActiveSession.persist.clientFiles.createRevision newClientFile, cb
				(cb) =>
					# Add a noticeable delay so that the user knows the save happened.
					setTimeout cb, 400
			], (err) =>
				@_unregisterTask 'updatePlan'

				if err
					if err instanceof Persist.IOError
						Bootbox.alert """
							An error occurred.  Please check your network connection and try again.
						"""
						return

					CrashHandler.handle err
					return

				# Nothing else to do.
				# Persist operations will automatically trigger event listeners
				# that update the UI.

		_registerListeners: ->
			registerTimeoutListeners()

			global.ActiveSession.persist.eventBus.on 'createRevision:clientFile', (newRev) =>
				if @state.isClosed
					return

				unless newRev.get('id') is clientFileId
					return

				@setState {clientFile: newRev}

			global.ActiveSession.persist.eventBus.on 'create:planTarget createRevision:planTarget', (newRev) =>
				if @state.isClosed
					return

				unless newRev.get('clientFileId') is clientFileId
					return

				@setState (state) =>
					targetId = newRev.get('id')

					if state.planTargetsById.has targetId
						planTargetsById = state.planTargetsById.updateIn [targetId, 'revisions'], (revs) =>
							return revs.unshift newRev
					else
						planTargetsById = state.planTargetsById.set targetId, Imm.fromJS {
							id: targetId
							revisions: [newRev]
						}

					return {planTargetsById}

			global.ActiveSession.persist.eventBus.on 'create:progNote', (newProgNote) =>
				if @state.isClosed
					return

				unless newProgNote.get('clientFileId') is clientFileId
					return

				@setState (state) =>
					return {
						progressNotes: state.progressNotes.push newProgNote
					}

			global.ActiveSession.persist.eventBus.on 'create:metric', (newMetric) =>
				if @state.isClosed
					return

				@setState (state) =>
					return {
						metricsById: state.metricsById.set newMetric.get('id'), newMetric
					}

		_unregisterListeners: ->
			unregisterTimeoutListeners()

			@setState {isClosed: true}

			if @state.clientFileLock
				@state.clientFileLock.release()

	ClientFilePageUi = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

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

			if @props.startupTasks.size > 0 or not @props.clientFile
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
					clientFile: @props.clientFile
					plan: @props.clientFile.get('plan')
					planTargetsById: @props.planTargetsById
					metricsById: @props.metricsById
					registerTask: @props.registerTask
					unregisterTask: @props.unregisterTask
					updatePlan: @props.updatePlan
				})
				ProgNotesTab.ProgNotesView({
					isVisible: activeTabId is 'progressNotes'
					clientFileId
					clientFile: @props.clientFile
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
		mixins: [React.addons.PureRenderMixin]
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
					R.span({}, renderFileId @props.recordId, true)
				)
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
		mixins: [React.addons.PureRenderMixin]
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
		mixins: [React.addons.PureRenderMixin]
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
