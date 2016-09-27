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


_ = require 'underscore'
Async = require 'async'
Imm = require 'immutable'
Moment = require 'moment'

Config = require '../config'
Term = require '../term'
Persist = require '../persist'


load = (win, {clientFileId}) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM
	Gui = win.require 'nw.gui'
	Window = Gui.Window.get(win)

	CrashHandler = require('../crashHandler').load(win)
	BrandWidget = require('../brandWidget').load(win)
	PlanTab = require('./planTab').load(win)
	ProgNotesTab = require('./progNotesTab').load(win)
	AnalysisTab = require('./analysisTab').load(win)
	InfoTab = require('./infoTab').load(win)
	OpenDialogLink = require('../openDialogLink').load(win)
	WithTooltip = require('../withTooltip').load(win)
	RenameClientFileDialog = require('../renameClientFileDialog').load(win)
	ClientAlerts = require('./clientAlerts').load(win)

	{
		handleCustomError, FaIcon, renderName,
		renderRecordId, showWhen, stripMetadata
	} = require('../utils').load(win)


	loadingSpinner = React.createFactory React.createClass
		displayName: 'loadingSpinner'
		mixins: [React.addons.PureRenderMixin]
		render: ->
			return R.div({className: "loadingSpinnerContainer"},
				R.div({className: "preloaderSpinner"},
					R.div({className: "spinnerContainer"},
						R.div({className: "rect10"})
						R.div({className: "rect20"})
						R.div({className: "rect30"})
						R.div({className: "rect40"})
						R.div({className: "rect50"})
					)
				)
			)


	ClientFilePage = React.createFactory React.createClass
		displayName: 'ClientFilePage'
		getInitialState: ->
			return {
				status: 'init' # Either init or ready

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
				planTemplateHeaders: Imm.List()
				detailDefinitionGroups: Imm.List()

				loadErrorType: null
				loadErrorData: null
			}


		init: ->
			@_renewAllData()

		deinit: (cb=(->)) ->
			@_killLocks cb

		suggestClose: ->
			@refs.ui.suggestClose()

		render: ->
			if @state.status isnt 'ready' then return loadingSpinner({})

			clientName = renderName(@state.clientFile.get('clientName'))

			# Order each individual progNoteHistory, then the overall histories
			progNoteHistories = @state.progNoteHistories
			.map (history) ->
				return history.sortBy (revision) -> revision.get('timestamp')
			.sortBy (history) ->
				createdAt = history.last().get('backdate') or history.first().get('timestamp')
				return Moment createdAt, Persist.TimestampFormat
			.reverse()

			# Use programLinks to determine program membership(s)
			# TODO: Refactor to clientProgramsById for faster searching by ID
			clientPrograms = @state.clientFileProgramLinkHeaders.map (link) =>
				programId = link.get('programId')
				return @state.programsById.get programId

			clientHasPrograms = not clientPrograms.isEmpty()

			# Filter to only global events that fit our criteria:
			# TODO: Move this up to data-load (issue #735)
			globalEvents = @state.globalEvents.filter (globalEvent) =>
				# Originally created from this clientFile
				return true if globalEvent.get('clientFileId') is clientFileId

				# GlobalEvent is fully global (no program)
				programId = globalEvent.get('programId')
				return true if not programId

				# globalEvent program matches up with one of clientFile's programs
				# TODO: This is one example of where we need to search clientPrograms by ID
				matchingProgram = clientPrograms.contains @state.programsById.get(programId)
				return true if matchingProgram

				# Failed criteria tests, so discard this globalEvent
				return false


			return ClientFilePageUi({
				ref: 'ui'

				status: @state.status
				readOnlyData: @state.readOnlyData
				loadErrorType: @state.loadErrorType

				clientFile: @state.clientFile
				clientName
				clientPrograms
				detailDefinitionGroups: @state.detailDefinitionGroups

				progNoteHistories
				progressEvents: @state.progressEvents
				planTargetsById: @state.planTargetsById
				metricsById: @state.metricsById
				planTemplateHeaders: @state.planTemplateHeaders
				programs: @state.programs
				programsById: @state.programsById
				clientFileProgramLinkHeaders: @state.clientFileProgramLinkHeaders
				eventTypes: @state.eventTypes
				globalEvents
				alerts: @state.alerts

				headerIndex: @state.headerIndex
				progNoteTotal: @state.progNoteTotal

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
			planTemplateHeaders = null
			planTargetsById = null
			planTargetHeaders = null
			progNoteHeaders = null
			progNoteHistories = null
			progNoteTotal = null
			progEventHeaders = null
			progressEvents = null
			metricHeaders = null
			metricsById = null
			clientDetailGroupsById = null
			clientFileProgramLinkHeaders = null
			programHeaders = null
			programs = null
			programsById = null
			eventTypeHeaders = null
			eventTypes = null
			globalEventHeaders = null
			globalEvents = null
			alertHeaders = null
			alerts = null
			groupsArray = null
			detailDefinitionHeaders = null
			detailDefinitionGroups = null


			checkFileSync = (newData, oldData) =>
				unless fileIsUnsync
					fileIsUnsync = not Imm.is oldData, newData

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

				(cb) =>
					ActiveSession.persist.alerts.list clientFileId, (err, result) =>
						if err
							cb err
							return
						alertHeaders = result
						cb()

				(cb) =>
					Async.map alertHeaders.toArray(), (alertHeader, cb) =>
						alertId = alertHeader.get('id')

						ActiveSession.persist.alerts.readLatestRevisions clientFileId, alertId, 1, cb
					, (err, results) =>
						if err
							cb err
							return

						alerts = Imm.List(results).map (alert) -> stripMetadata alert.get(0)
						cb()

				(cb) =>
					ActiveSession.persist.planTemplates.list (err, result) =>
						if err
							cb err
							return

						planTemplateHeaders = result
						.filter (template) -> template.get('status') is 'default'
						cb()

				(cb) =>
					ActiveSession.persist.clientDetailDefinitionGroups.list (err, result) =>
						if err
							cb err
							return

						detailDefinitionHeaders = result
						cb()

				(cb) =>
					# Check to see whether detailGroups (from Config) have been created yet
					if detailDefinitionHeaders.size > 0 or Config.clientDetailDefinitionGroups is 0
						cb()
						return

					# Ok, we need to seed the definitions objects from config (FRESH RUN)
					newDetailDefinitionGroups = Config.clientDetailDefinitionGroups.map (group) =>
						fields = group.fields.map (field) =>
							return {
								id: Persist.generateId()
								name: field.name
								inputType: field.inputType
								placeholder: field.placeholder
							}

						Imm.fromJS {
							title: group.title
							status: 'default'
							fields
						}

					Async.map newDetailDefinitionGroups, (obj, cb) =>
						ActiveSession.persist.clientDetailDefinitionGroups.create obj, (err, result) =>
							if err
								cb err
								return

							newGroup = result
							cb(null, result)
					, (err, results) ->
						if err
							cb err
							return

						# Not actually headers, but we use them as such
						detailDefinitionHeaders = Imm.List(results)
						cb()

				(cb) =>
					Async.map detailDefinitionHeaders.toArray(), (clientDetailGroupHeader, cb) =>
						clientDetailGroupId = clientDetailGroupHeader.get('id')

						ActiveSession.persist.clientDetailDefinitionGroups.readLatestRevisions clientDetailGroupId, 1, cb
					, (err, results) =>
						if err
							cb err
							return

						detailDefinitionGroups = Imm.List(results).map (clientDetailGroup) =>
							stripMetadata clientDetailGroup.first()

						checkFileSync detailDefinitionGroups, @state.detailDefinitionGroups
						cb()

			], (err) =>
				if err
					# Cancel any lock operations, and show the page in error
					@_killLocks()
					global.ActiveSession.persist.eventBus.trigger 'clientFilePage:loaded'
					Window.show()

					if err instanceof Persist.CustomError
						handleCustomError err
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

						headerIndex: @state.headerIndex+10
						progNoteTotal

						clientFile
						progNoteHistories
						progressEvents
						globalEvents
						metricsById
						planTargetsById
						planTemplateHeaders
						programs
						programsById
						detailDefinitionGroups
						clientFileProgramLinkHeaders
						eventTypes
						alerts
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
										icon: Config.iconNotification
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

			], (err) =>
				if err
					if err instanceof Persist.CustomError
						handleCustomError err
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
								revisions: Imm.List [newRev]
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

				'create:planTemplate': (newTemplate) =>
					planTemplateHeaders = @state.planTemplateHeaders.push newTemplate
					@setState {planTemplateHeaders}


				'create:eventType': (newEventType) =>
					eventTypes = @state.eventTypes.push newEventType
					@setState {eventTypes}

				'createRevision:eventType': (newEventTypeRev) =>
					originalEventType = @state.eventTypes
					.find (eventType) -> eventType.get('id') is newEventTypeRev.get('id')

					eventTypeIndex = @state.eventTypes.indexOf originalEventType
					eventTypes = @state.eventTypes.set eventTypeIndex, newEventTypeRev
					@setState {eventTypes}

				'create:program': (newProgram) =>
					programs = @state.programs.push newProgram
					@setState {programs}

				'createRevision:program': (newProgramRev) =>
					originalProgram = @state.programs
					.find (program) -> program.get('id') is program.get('id')

					programIndex = @state.programs.indexOf originalProgram
					programs = @state.programs.set programIndex, newProgramRev
					@setState {programs}

				'create:globalEvent': (globalEvent) =>
					globalEvents = @state.globalEvents.push globalEvent
					@setState {globalEvents}

				# TODO: Update to allow for multiple alerts
				'create:alert createRevision:alert': (alert) =>
					alerts = Imm.List [alert]
					@setState {alerts}

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
			# TODO: Make this a little nicer
			if @refs.planTab?
				@refs.planTab.hasChanges()
			else if @refs.sidebar
				@refs.sidebar.hasChanges()
			else if @refs.infoTab?
			 	@refs.infoTab.hasChanges()
			else
				false

		suggestClose: ->
			return unless @hasMounted

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
			else if @refs.sidebar.hasChanges()
				Bootbox.confirm "Discard unsaved changes to #{Term 'client'} alerts?", (ok) =>
					if ok then @props.closeWindow()

			else if @refs.infoTab.hasChanges()
				Bootbox.dialog {
					title: "Unsaved Changes to #{Term 'Client File'}"
					message: """
						You have unsaved changes in Client Information for #{clientName}.
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
							label: "View Additional Information"
							className: "btn-success"
							callback: =>
								Bootbox.hideAll()
								@setState {activeTabId: 'info'}
						}
					}
				}
			else
				@props.closeWindow()

		componentDidMount: ->
			@props.setWindowTitle "#{Config.productName} (#{global.ActiveSession.userName}) - #{@props.clientName}"
			Window.focus()
			Window.maximize()

			# It's now OK to close the window
			@hasMounted = true

		render: ->
			if @props.loadErrorType
				return LoadError {
					loadErrorType: @props.loadErrorType
					closeWindow: @props.closeWindow
				}

			activeTabId = @state.activeTabId
			isReadOnly = @props.readOnlyData?

			recordId = @props.clientFile.get('recordId')


			return R.div({className: 'clientFilePage animated fadeIn'},

				(if isReadOnly
					ReadOnlyNotice {data: @props.readOnlyData}
				)
				R.div({className: 'wrapper'},
					Sidebar({
						ref: 'sidebar'
						clientFile: @props.clientFile
						clientName: @props.clientName
						clientPrograms: @props.clientPrograms
						recordId
						activeTabId
						programs: @props.programs
						status: @props.clientFile.get('status')
						alerts: @props.alerts
						onTabChange: @_changeTab
						isReadOnly
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
							planTemplateHeaders: @props.planTemplateHeaders
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
					R.div({
						className: [
							'view'
							showWhen(activeTabId is 'info')
						].join ' '
					},
						InfoTab.InfoView({
							ref: 'infoTab'
							clientFileId
							clientFile: @props.clientFile
							programsById: @props.programsById
							detailDefinitionGroups: @props.detailDefinitionGroups
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

		hasChanges: ->
			# Pass up clientAlerts.hasChanges() to UI parent
			@refs.clientAlerts.hasChanges()

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

				(if @props.status is 'inactive'
					R.div({className: 'inactiveStatus'},
						@props.status.toUpperCase()
					)
				else if @props.status is 'discharged'
					R.div({className: 'dischargedStatus'},
						@props.status.toUpperCase()
					)
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
					SidebarTab({
						name: "Client Information"
						icon: 'info'
						isActive: activeTabId is 'info'
						onClick: @props.onTabChange.bind null, 'info'
					})
				)

				ClientAlerts({
					ref: 'clientAlerts'
					alerts: @props.alerts
					clientFileId
					isDisabled: @props.isReadOnly
				})

				BrandWidget()
			)


	SidebarTab = React.createFactory React.createClass
		displayName: 'SidebarTab'

		render: ->
			return R.div({
				className: "tab #{if @props.isActive then 'active' else ''}"
				onClick: @props.onClick
			},
				FaIcon @props.icon
				' '
				@props.name
			)


	ReadOnlyNotice = React.createFactory React.createClass
		displayName: 'ReadOnlyNotice'

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
