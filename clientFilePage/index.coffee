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
Imm = require 'immutable'
Moment = require 'moment'

Config = require '../config'
Persist = require '../persist'

load = (win, {clientId}) ->
	# Libraries from browser context
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM
	Gui = win.require 'nw.gui'
	Spinner = require('../spinner').load(win)
	BrandWidget = require('../brandWidget').load(win)
	PlanTab = require('./planTab').load(win)
	ProgNotesTab = require('./progNotesTab').load(win)
	{FaIcon, renderName, showWhen} = require('../utils').load(win)

	nwWin = Gui.Window.get(win)

	DataStore = do ->
		clientFile = null
		progressNotes = null
		planTargetsById = Imm.Map()
		metricsById = Imm.Map()
		startupTasks = Imm.Set() # set of task IDs
		ongoingTasks = Imm.Set() # set of task IDs
		isClosed = false

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

				# Data store methods
				registerTask
				unregisterTask
				loadData
				loadMetric
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
			registerTask 'readClientFile', true
			Persist.ClientFile.readLatestRevisions clientId, 1, (err, revisions) =>
				if err
					unregisterTask 'readClientFile', true
					console.error err.stack
					Bootbox.alert "Could not load client data."
					return

				clientFile = Imm.fromJS revisions[0]

				# Load plan targets
				registerTask "readPlanTargets", true
				Persist.PlanTarget.readClientFileTargets clientFile, (err, result) =>
					if err
						unregisterTask "readPlanTargets", true
						console.error err.stack
						Bootbox.alert "Could not load client data."
						return

					planTargetsById = result

					# Load metrics
					planTargetsById.valueSeq().forEach (target) =>
						target.getIn(['revisions', 0, 'metricIds']).forEach (metricId) =>
							loadMetric metricId, true

					unregisterTask "readPlanTargets", true

				unregisterTask 'readClientFile', true

			registerTask 'readProgressNotes', true
			Persist.ProgNote.readAll clientId, (err, results) =>
				if err
					unregisterTask 'readProgressNotes', true
					console.error err.stack
					Bootbox.alert "Error loading progress notes"
					return

				progressNotes = Imm.fromJS results
				unregisterTask 'readProgressNotes', true

			registerTask 'listMetrics', true
			Persist.Metric.list (err, results) ->
				if err
					unregisterTask 'listMetrics', true
					console.error err.stack
					Bootbox.alert "Error listing metrics"
					return

				results.forEach (metricHeader) ->
					loadMetric metricHeader.get('id')

				unregisterTask 'listMetrics', true

		loadMetric = (metricId, isStartupTask=false, cb=(->)) ->
			taskId = "readMetric.#{metricId}"

			# If already loaded or being loaded
			if metricsById.has(metricId) or startupTasks.has(taskId)
				cb()
				return

			registerTask taskId, isStartupTask
			Persist.Metric.readLatestRevisions metricId, 1, (err, revisions) =>
				if err
					unregisterTask taskId, isStartupTask
					console.error err.stack
					return

				metricsById = metricsById.set metricId, revisions[0]

				unregisterTask taskId, isStartupTask
				cb()

		updateClientFile = (context, newValue) ->
			clientFile = clientFile.setIn context, newValue

			registerTask "updateClientFile"
			Persist.ClientFile.createRevision clientFile, (err) =>
				unregisterTask "updateClientFile"

				if err
					console.error err.stack
					Bootbox.alert "An error occurred while updating the client file."
					return

				console.log "Client file update successful."

				# Add a delay so that the user knows it saved
				slowSaveTaskId = "slow-save-#{Persist.generateId()}"
				registerTask slowSaveTaskId
				setTimeout unregisterTask.bind(null, slowSaveTaskId), 500

		registerListeners = ->
			global.EventBus.on 'newPlanTargetRevision', (newRev) ->
				if isClosed
					return

				unless newRev.get('clientId') is clientId
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

			global.EventBus.on 'newProgNote', (newProgNote) ->
				if isClosed
					return

				unless newProgNote.get('clientId') is clientId
					return

				progressNotes = progressNotes.push newProgNote

				render()

			global.EventBus.on 'newMetricRevision', (newRev) ->
				if isClosed
					return

				metricsById = metricsById.set newRev.get('id'), newRev

				render()

		unregisterListeners = ->
			isClosed = true

		return {}

	ClientPage = React.createFactory React.createClass
		getInitialState: ->
			return {
				activeTabId: 'plan'
			}
		componentWillMount: ->
			nwWin.maximize()
			nwWin.on 'close', (event) =>
				# TODO handle this
				@props.unregisterListeners()
				nwWin.close(true)
				return

				# If page still loading
				# TODO handle this more elegantly
				unless @props.clientFile?
					nwWin.close true
					return

				# TODO this needs to check if plan tab has changes
				if @_hasChanges()
					Bootbox.dialog {
						message: "There are unsaved changes in this client file."
						buttons: {
							discard: {
								label: "Discard changes"
								className: 'btn-danger'
								callback: =>
									nwWin.close true
							}
							cancel: {
								label: "Cancel"
								className: 'btn-default'
							}
							save: {
								label: "Save changes"
								className: 'btn-primary'
								callback: =>
									@_save =>
										process.nextTick =>
											nwWin.close()
							}
						}
					}
				else if @_hasChanges()
					Bootbox.confirm "
						#{Config.productName} is busy saving your work.
						Are you sure you want to interrupt it?
					", (confirmed) ->
						if confirmed
							nwWin.close true
				else if @_isWorking()
					Bootbox.confirm "
						#{Config.productName} is busy working right now.
						Are you sure you want to interrupt it?
					", (confirmed) ->
						if confirmed
							nwWin.close true
				else
					nwWin.close(true)
		render: ->
			if @props.startupTasks.size > 0 or not @props.clientFile
				return R.div({className: 'clientFilePage'},
					Spinner({isOverlay: true, isVisible: true})
				)

			activeTabId = @state.activeTabId

			clientName = renderName @props.clientFile.get('clientName')
			nwWin.title = "#{clientName} - KoNote"

			return R.div({className: 'clientFilePage'},
				Spinner({isOverlay: true, isVisible: @props.ongoingTasks.size > 0})
				Sidebar({
					clientName
					activeTabId
					onTabChange: @_changeTab
				})
				PlanTab.PlanView({
					isVisible: activeTabId is 'plan'
					clientId
					plan: @props.clientFile.get('plan')
					planTargetsById: @props.planTargetsById
					metricsById: @props.metricsById
					registerTask: @props.registerTask
					unregisterTask: @props.unregisterTask
					updatePlan: @props.updateClientFile.bind null, ['plan']
					loadMetric: @props.loadMetric
				})
				ProgNotesTab.ProgNotesView({
					isVisible: activeTabId is 'progressNotes'
					clientId
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
						name: "Metrics"
						icon: 'line-chart'
						isActive: activeTabId is 'metrics'
						onClick: @props.onTabChange.bind null, 'metrics'
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

module.exports = {load}
