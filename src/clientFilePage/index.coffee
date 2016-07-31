# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

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
Assert = require 'assert'
Async = require 'async'
Imm = require 'immutable'
Moment = require 'moment'

Config = require '../config'
Term = require '../term'
Persist = require '../persist'

load = (win, {clientFileId}) ->
	# Libraries from browser context
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM
	Gui = win.require 'nw.gui'
	Window = Gui.Window.get(win)

	CrashHandler = require('../crashHandler').load(win)
	Spinner = require('../spinner').load(win)
	BrandWidget = require('../brandWidget').load(win)
	PlanTab = require('./planTab').load(win)
	ProgNotesTab = require('./progNotesTab').load(win)
	AnalysisTab = require('./analysisTab').load(win)
	OpenDialogLink = require('../openDialogLink').load(win)
	WithTooltip = require('../withTooltip').load(win)
	RenameClientFileDialog = require('../renameClientFileDialog').load(win)

	{FaIcon, renderName, renderRecordId, showWhen, stripMetadata} = require('../utils').load(win)

	ClientFilePage = React.createFactory React.createClass
		displayName: 'ClientFilePage'
		getInitialState: ->
			return {
				status: 'init' # Either init or ready
				isLoading: false

				headerIndex: 0

				clientFile: null
				clientFileLock: null
				readOnlyData: null
				lockOperation: null

				progNoteHistories: null
				progNoteTotal: null
				progressEvents: null
				planTargetsById: Imm.Map()
				programsById: Imm.Map()
				metricsById: Imm.Map()
				loadErrorType: null
				loadErrorData: null
			}

		init: ->
			@_renewAllData()

		_setIsLoading: (isLoading) ->
			@setState {isLoading}

		deinit: (cb=(->)) ->
			@_killLocks cb

		suggestClose: ->
			@refs.ui.suggestClose()

		render: ->
			if @state.status isnt 'ready' then return R.div({})


			clientName = renderName(@state.clientFile.get('clientName'))

			# Order each individual progNoteHistory, then the overall histories
			progNoteHistories = @state.progNoteHistories
			.map (history) ->
				return history.sortBy (revision) -> +Moment(revision.get('timestamp'), Persist.TimestampFormat)
			.sortBy (history) ->
				createdAt = history.last().get('backdate') or history.first().get('timestamp')
				return Moment createdAt, Persist.TimestampFormat
			.reverse()

			# Use programLinks to determine program membership(s)
			clientPrograms = @state.clientFileProgramLinkHeaders.map (link) =>
				programId = link.get('programId')
				@state.programsById.get programId

			clientFileCreated = Moment @state.clientFile.get('timestamp'), Persist.TimestampFormat

			# Filter out global events that either belong to this clientFile,
			# or span (entirely) outside its history
			globalEvents = @state.globalEvents.filterNot (globalEvent) =>
				return true if globalEvent.get('clientFileId') is clientFileId

				eventStarted = Moment globalEvent.get('startTimestamp'), Persist.TimestampFormat
				eventEnded = Moment globalEvent.get('endTimestamp'), Persist.TimestampFormat
				return eventStarted.isAfter(clientFileCreated) or eventEnded.isAfter(clientFileCreated)


			return ClientFilePageUi({
				ref: 'ui'

				status: @state.status
				isLoading: @state.isLoading
				readOnlyData: @state.readOnlyData
				loadErrorType: @state.loadErrorType

				clientFile: @state.clientFile
				clientName
				clientPrograms

				progNoteHistories
				progressEvents: @state.progressEvents
				planTargetsById: @state.planTargetsById
				metricsById: @state.metricsById
				programs: @state.programs
				programsById: @state.programsById
				clientFileProgramLinkHeaders: @state.clientFileProgramLinkHeaders
				eventTypes: @state.eventTypes
				globalEvents

				headerIndex: @state.headerIndex
				progNoteTotal: @state.progNoteTotal

				setIsLoading: @_setIsLoading
				closeWindow: @props.closeWindow
				setWindowTitle: @props.setWindowTitle
				updatePlan: @_updatePlan

				renewAllData: @_renewAllData
			})

		_renewAllData: ->
			console.log "Renewing all data......"

			# Sync check
			fileIsUnsync = null
			# File data
			clientFile = null
			planTargetsById = null
			planTargetHeaders = null
			progNoteHeaders = null
			progNoteHistories = null
			progNoteTotal = null
			progEventHeaders = null
			progressEvents = null
			metricHeaders = null
			metricsById = null
			clientFileProgramLinkHeaders = null
			programHeaders = null
			programs = null
			programsById = null
			eventTypeHeaders = null
			eventTypes = null
			globalEventHeaders = null
			globalEvents = null

			checkFileSync = (newData, oldData) =>
				unless fileIsUnsync
					fileIsUnsync = not Imm.is oldData, newData

			@setState -> {isLoading: true}

			# Begin the clientFile data load process
			Async.series [
				(cb) =>
					unless @state.clientFileLock?
						@_acquireLock cb
					else
						cb()

				(cb) =>
					ActiveSession.persist.clientFiles.readLatestRevisions clientFileId, 1, (err, revisions) =>
						if err
							cb err
							return

						clientFile = stripMetadata revisions.get(0)

						checkFileSync clientFile, @state.clientFile
						cb()

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

						planTargetsById = Imm.List(results).map (planTargetRevs) =>
							id = planTargetRevs.getIn([0, 'id'])
							return [
								id
								Imm.Map({id, revisions: planTargetRevs.reverse()})
							]
						.fromEntrySeq().toMap()

						checkFileSync planTargetsById, @state.planTargetsById
						cb()

				(cb) =>
					ActiveSession.persist.progNotes.list clientFileId, (err, results) =>
						if err
							cb err
							return

						# lazyloading
						progNoteTotal = results.size
						progNoteHeaders = results
						# .sortBy (header) ->
						# 	createdAt = header.get('backdate') or header.get('timestamp')
						# 	return Moment createdAt, Persist.TimestampFormat
						# .reverse()
						# .slice(@state.headerIndex, @state.headerIndex+10)
						cb()

				(cb) =>
					Async.map progNoteHeaders.toArray(), (progNoteHeader, cb) =>
						ActiveSession.persist.progNotes.readRevisions clientFileId, progNoteHeader.get('id'), cb
					, (err, results) =>
						if err
							cb err
							return

						progNoteHistories = Imm.List(results)

						checkFileSync progNoteHistories, @state.progNoteHistories
						cb()

				(cb) =>
					ActiveSession.persist.progEvents.list clientFileId, (err, results) =>
						if err
							cb err
							return

						progEventHeaders = results
						cb()

				(cb) =>
					Async.map progEventHeaders.toArray(), (progEventHeader, cb) =>
						ActiveSession.persist.progEvents.readLatestRevisions clientFileId, progEventHeader.get('id'), 1, cb
					, (err, results) =>
						if err
							cb err
							return

						progressEvents = Imm.List(results)
						.map (progEvent) -> stripMetadata progEvent.first()

						checkFileSync progressEvents, @state.progressEvents
						cb()

				(cb) =>
					ActiveSession.persist.globalEvents.list (err, results) =>
						if err
							cb err
							return

						globalEventHeaders = results
						cb()

				(cb) =>
					Async.map globalEventHeaders.toArray(), (globalEventHeader, cb) =>
						ActiveSession.persist.globalEvents.readLatestRevisions globalEventHeader.get('id'), 1, cb
					, (err, results) =>
						if err
							cb err
							return

						globalEvents = Imm.List(results).map (revisions) -> revisions.first()
						cb()

				(cb) =>
					ActiveSession.persist.metrics.list (err, results) =>
						if err
							cb err
							return

						metricHeaders = results
						cb()

				(cb) =>
					Async.map metricHeaders.toArray(), (metricHeader, cb) =>
						ActiveSession.persist.metrics.readLatestRevisions metricHeader.get('id'), 1, cb
					, (err, results) =>
						if err
							cb err
							return

						metricsById = Imm.List(results)
						.map (metric) =>
							metric = stripMetadata metric.first()
							return [metric.get('id'), metric]
						.fromEntrySeq().toMap()

						checkFileSync metricsById, @state.metricsById
						cb()

				(cb) =>
					ActiveSession.persist.clientFileProgramLinks.list (err, results) =>
						if err
							cb err
							return

						clientFileProgramLinkHeaders = results
						.filter (link) ->
							link.get('clientFileId') is clientFileId and
							link.get('status') is "enrolled"

						cb()

				(cb) =>
					ActiveSession.persist.programs.list (err, results) =>
						if err
							cb err
							return

						programHeaders = results

						cb()

				(cb) =>
					Async.map programHeaders.toArray(), (programHeader, cb) =>
						ActiveSession.persist.programs.readLatestRevisions programHeader.get('id'), 1, cb
					, (err, results) =>
						if err
							cb err
							return

						programs = Imm.List(results)
						.map (program) -> stripMetadata program.get(0)

						programsById = programs
						.map (program) -> [program.get('id'), program]
						.fromEntrySeq().toMap()

						checkFileSync programs, @state.programs
						cb()

				(cb) =>
					ActiveSession.persist.eventTypes.list (err, result) =>
						if err
							cb err
							return

						eventTypeHeaders = result
						cb()

				(cb) =>
					Async.map eventTypeHeaders.toArray(), (eventTypeheader, cb) =>
						eventTypeId = eventTypeheader.get('id')

						ActiveSession.persist.eventTypes.readLatestRevisions eventTypeId, 1, cb
					, (err, results) =>
						if err
							cb err
							return

						eventTypes = Imm.List(results).map (eventType) -> stripMetadata eventType.get(0)
						cb()

			], (err) =>
				if err
					# Cancel any lock operations, and show the page in error
					@_killLocks()
					global.ActiveSession.persist.eventBus.trigger 'clientFilePage:loaded'
					Window.show()

					if err instanceof Persist.IOError
						console.error err
						console.error err.stack

						@setState {loadErrorType: 'io-error', status: 'ready'}
						return

					CrashHandler.handle err
					return

				# Trigger readOnly mode when hasChanges and unsynced
				if @state.clientFile? and @refs.ui.hasChanges() and fileIsUnsync
					console.log "Handling remote changes vs local changes..."

					@setState {
						status: 'ready'
						readOnlyData: {
							message: "Please back up your changes, and click here to reload the file"
							clickAction: => @props.refreshWindow()
						}
					}, =>
						clientName = renderName @state.clientFile.get('clientName')
						Bootbox.dialog {
							title: "Refresh #{Term 'Client File'}?"
							message: "This #{Term 'client file'} for #{clientName} has been
								revised since your session timed out. This #{Term 'file'}
								must be refreshed, and your unsaved changes will be lost!
								What would you like to do?"
							buttons: {
								cancel: {
									label: "I'll back up my changes first"
									className: 'btn-success'
								}
								success: {
									label: "Reload #{Term 'client file'} now"
									className: 'btn-warning'
									callback: => @props.refreshWindow()
								}
							}
						}
				else
					@setState {
						status: 'ready'
						isLoading: false

						headerIndex: @state.headerIndex+10
						progNoteTotal

						clientFile
						progNoteHistories
						progressEvents
						globalEvents
						metricsById
						planTargetsById
						programs
						programsById
						clientFileProgramLinkHeaders
						eventTypes
					}

		_acquireLock: (cb=(->)) ->
			lockFormat = "clientFile-#{clientFileId}"

			Persist.Lock.acquire global.ActiveSession, lockFormat, (err, lock) =>
				if err
					if err instanceof Persist.Lock.LockInUseError

						pingInterval = Config.clientFilePing.acquireLock

						# Prepare readOnly message
						lockOwner = err.metadata.userName
						readOnlyMessage = if lockOwner is global.ActiveSession.userName
							"You already have this file open in another window"
						else
							"File currently in use by username: \"#{lockOwner}\""

						@setState {
							readOnlyData: {message: readOnlyMessage}

							# Keep checking for lock availability, returns new lock when true
							lockOperation: Persist.Lock.acquireWhenFree global.ActiveSession, lockFormat, pingInterval, (err, newLock) =>
								if err
									cb err
									return

								if newLock
									# Alert user about lock acquisition
									clientName = renderName @state.clientFile.get('clientName')
									new win.Notification "#{clientName} file unlocked", {
										body: "You now have the read/write permissions for this #{Term 'client file'}"
									}
									@setState {
										clientFileLock: newLock
										readOnlyData: null
									}, @_renewAllData
								else
									console.log "acquireWhenFree operation cancelled"
						}, cb
					else
						cb err

				else
					@setState {
						clientFileLock: lock
						readOnlyData: null
						lockOperation: null
					}, cb

		_killLocks: (cb=(->)) ->
			console.log "Releasing any active locks/operations...."

			if @state.clientFileLock?
				console.log "Releasing existing lock..."
				@state.clientFileLock.release(=>
					@setState {clientFileLock: null}, =>
						console.log "Lock released!"
						cb()
				)
			else if @state.lockOperation?
				console.log "Killing lockOperation..."
				@state.lockOperation.cancel cb
			else
				console.log "None to release, closing..."
				cb()

		_updatePlan: (plan, newPlanTargets, updatedPlanTargets) ->
			@setState (state) => {isLoading: true}

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
				@setState (state) => {isLoading: false}

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

		getPageListeners: ->
			return {
				'createRevision:clientFile': (newRev) =>
					return unless newRev.get('id') is clientFileId
					@setState {clientFile: newRev}

				'create:planTarget createRevision:planTarget': (newRev) =>
					return unless newRev.get('clientFileId') is clientFileId
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

				'create:progNote': (newProgNote) =>
					return unless newProgNote.get('clientFileId') is clientFileId

					@setState (state) =>
						return {
							progNoteHistories: state.progNoteHistories.push Imm.List([newProgNote])
						}

				'createRevision:progNote': (newProgNoteRev) =>
					return unless newProgNoteRev.get('clientFileId') is clientFileId

					@setState (state) =>
						return {
							progNoteHistories: state.progNoteHistories.map (progNoteHist) =>
								if progNoteHist.first().get('id') is newProgNoteRev.get('id')
									return progNoteHist.push newProgNoteRev

								return progNoteHist
						}

				'create:progEvent': (newProgEvent) =>
					return unless newProgEvent.get('clientFileId') is clientFileId
					progressEvents = @state.progressEvents.push newProgEvent
					@setState {progressEvents}

				'createRevision:progEvent': (newProgEventRev) =>
					return unless newProgEventRev.get('clientFileId') is clientFileId
					originalProgEvent = @state.progressEvents
					.find (progEvent) -> progEvent.get('id') is newProgEventRev.get('id')

					progEventIndex = @state.progressEvents.indexOf originalProgEvent
					progressEvents = @state.progressEvents.set progEventIndex, newProgEventRev
					@setState {progressEvents}

				'create:metric createRevision:metric': (metricDefinition) =>
					metricsById = @state.metricsById.set metricDefinition.get('id'), metricDefinition
					@setState {metricsById}

				'create:eventType': (newEventType) =>
					eventTypes = @state.eventTypes.push newEventType
					@setState {eventTypes}

				'createRevision:eventType': (newEventTypeRev) =>
					originalEventType = @state.eventTypes
					.find (eventType) -> eventType.get('id') is newEventTypeRev.get('id')

					eventTypeIndex = @state.eventTypes.indexOf originalEventType
					eventTypes = @state.eventTypes.set eventTypeIndex, newEventTypeRev
					@setState {eventTypes}

				'create:globalEvent': (globalEvent) =>
					globalEvents = @state.globalEvents.push globalEvent
					@setState {globalEvents}

				'timeout:timedOut': =>
					@_killLocks Bootbox.hideAll

				'timeout:reactivateWindows': =>
					@_renewAllData()
			}



	ClientFilePageUi = React.createFactory React.createClass
		displayName: 'ClientFilePageUi'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				activeTabId: 'plan'
			}

		hasChanges: ->
			# Eventually this will cover more
			# components where unsaved changes can occur
			if @refs.planTab?
				@refs.planTab.hasChanges()
			else
				false

		suggestClose: ->
			# If page still loading
			# TODO handle this more elegantly
			unless @props.clientFile?
				@props.closeWindow()
				return

			clientName = renderName @props.clientFile.get('clientName')

			if @refs.planTab.hasChanges()
				Bootbox.dialog {
					title: "Unsaved Changes to #{Term 'Plan'}"
					message: """
						You have unsaved changes in this #{Term 'plan'} for #{clientName}.
						How would you like to proceed?
					"""
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
								@props.closeWindow()
						}
						success: {
							label: "View #{Term 'Plan'}"
							className: "btn-success"
							callback: =>
								Bootbox.hideAll()
								@setState {activeTabId: 'plan'}, @refs.planTab.blinkUnsaved
						}
					}
				}
			else if @refs.progNotesTab.hasChanges()
				Bootbox.dialog {
					title: "Unsaved Changes to #{Term 'Progress Note'}"
					message: """
						You have unsaved changes to a #{Term 'progress note'}.
						How would you like to proceed?
					"""
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
								@props.closeWindow()
						}
						success: {
							label: "View #{Term 'Progress Note'}"
							className: "btn-success"
							callback: =>
								Bootbox.hideAll()
								@setState {activeTabId: 'progressNotes'}
						}
					}
				}
			else
				@props.closeWindow()

		componentDidMount: ->
			global.ActiveSession.persist.eventBus.trigger 'clientFilePage:loaded'

			@props.setWindowTitle "#{Config.productName} (#{global.ActiveSession.userName}) - #{@props.clientName}"
			Window.focus()

		render: ->
			if @props.loadErrorType
				return LoadError {
					loadErrorType: @props.loadErrorType
					closeWindow: @props.closeWindow
				}

			activeTabId = @state.activeTabId
			isReadOnly = @props.readOnlyData?

			recordId = @props.clientFile.get('recordId')


			return R.div({className: 'clientFilePage'},
				Spinner {
					isOverlay: true
					isVisible: @props.isLoading
				}

				(if isReadOnly
					ReadOnlyNotice {data: @props.readOnlyData}
				)
				R.div({className: 'wrapper'},
					Sidebar({
						clientFile: @props.clientFile
						clientName: @props.clientName
						clientPrograms: @props.clientPrograms
						recordId
						activeTabId
						programs: @props.programs
						status: @props.clientFile.get('status')
						onTabChange: @_changeTab
					})
					R.div({
						className: [
							'view'
							showWhen(activeTabId is 'plan')
						].join ' '
					},
						PlanTab.PlanView({
							ref: 'planTab'
							clientFileId
							clientFile: @props.clientFile
							plan: @props.clientFile.get('plan')
							planTargetsById: @props.planTargetsById
							programsById: @props.programsById
							metricsById: @props.metricsById
							updatePlan: @props.updatePlan
							isReadOnly
						})
					)
					R.div({
						className: [
							'view'
							showWhen(activeTabId is 'progressNotes')
						].join ' '
					},
						ProgNotesTab({
							ref: 'progNotesTab'
							clientFileId
							clientFile: @props.clientFile
							clientPrograms: @props.clientPrograms
							globalEvents: @props.globalEvents
							progNoteHistories: @props.progNoteHistories
							planTargetsById: @props.planTargetsById
							progEvents: @props.progressEvents
							eventTypes: @props.eventTypes
							metricsById: @props.metricsById
							headerIndex: @props.headerIndex
							progNoteTotal: @props.progNoteTotal
							programsById: @props.programsById

							hasChanges: @hasChanges
							onTabChange: @_changeTab

							renewAllData: @props.renewAllData

							isLoading: @props.isLoading
							setIsLoading: @props.setIsLoading
							isReadOnly
						})
					)
					R.div({
						className: [
							'view'
							showWhen(activeTabId is 'analysis')
						].join ' '
					},
						AnalysisTab.AnalysisView({
							ref: 'analysisTab'
							clientFileId
							clientName: @props.clientName
							plan: @props.clientFile.get('plan')
							planTargetsById: @props.planTargetsById
							progNoteHistories: @props.progNoteHistories
							progEvents: @props.progressEvents
							eventTypes: @props.eventTypes
							metricsById: @props.metricsById
							globalEvents: @props.globalEvents
							isReadOnly
						})
					)
				)
			)

		_changeTab: (activeTabId) ->
			@setState {activeTabId}

	Sidebar = React.createFactory React.createClass
		displayName: 'Sidebar'
		mixins: [React.addons.PureRenderMixin]

		render: ->
			activeTabId = @props.activeTabId

			return R.div({className: 'sidebar'},
				R.img({src: Config.logoCustomerLg}),
				R.div({className: 'logoSubtitle'},
					Config.logoSubtitle
				)
				R.div({className: 'clientName'},
					(if ActiveSession.accountType is 'admin'
						WithTooltip({title: "Edit Client Information", placement: 'right', container: 'body'},
							OpenDialogLink({
								dialog: RenameClientFileDialog
								clientFile: @props.clientFile
								className: 'clientNameField'
							},
								@props.clientName
							)
						)
					else
						@props.clientName
					)
				)
				(if not @props.clientPrograms.isEmpty()
					R.div({className: 'programs'},
						(@props.clientPrograms.map (program) ->
							R.span({
								key: program.get('id')
								style:
									borderBottomColor: program.get('colorKeyHex')
							},
								program.get('name')
							)
						)
					)
				)
				(if @props.recordId
					R.div({className: 'recordId'},
						R.span({}, renderRecordId @props.recordId, true)
					)
				)
				if @props.status is 'inactive'
					R.div({className: 'inactiveStatus'},
						@props.status.toUpperCase()
					)
				else if @props.status is 'discharged'
					R.div({className: 'dischargedStatus'},
						@props.status.toUpperCase()
					)
				R.div({className: 'tabStrip'},
					SidebarTab({
						name: Term('Plan')
						icon: 'sitemap'
						isActive: activeTabId is 'plan'
						onClick: @props.onTabChange.bind null, 'plan'
					})
					SidebarTab({
						name: Term('Progress Notes')
						icon: 'pencil-square-o'
						isActive: activeTabId is 'progressNotes'
						onClick: @props.onTabChange.bind null, 'progressNotes'
					})
					SidebarTab({
						name: Term('Analysis')
						icon: 'line-chart'
						isActive: activeTabId is 'analysis'
						onClick: @props.onTabChange.bind null, 'analysis'
					})
				)
				BrandWidget()
			)

	SidebarTab = React.createFactory React.createClass
		displayName: 'SidebarTab'
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
		displayName: 'LoadError'
		mixins: [React.addons.PureRenderMixin]
		componentDidMount: ->
			console.log "loadErrorType:", @props.loadErrorType
			msg = switch @props.loadErrorType
				when 'io-error'
					"""
						An error occurred while loading the #{Term 'client file'}.
						This may be due to a problem with your network connection.
					"""
				else
					"An unknown error occured (loadErrorType: #{@props.loadErrorType}"
			Bootbox.alert msg, =>
				@props.closeWindow()
		render: ->
			return R.div({className: 'clientFilePage'})

	ReadOnlyNotice = React.createFactory React.createClass
		displayName: 'ReadOnlyNotice'
		mixins: [React.addons.PureRenderMixin]
		render: ->
			return R.div({className: 'readOnlyNotice'},
				R.div({
					className: [
						"notice"
						"clickable" if @props.data.clickAction?
					].join ' '
					onClick: @props.data.clickAction
				},
					@props.data.message
				)
				R.div({className: 'mode'},
					@props.data.mode or "Read-Only Mode"
				)
			)

	return ClientFilePage

module.exports = {load}
