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
	Window = nw.Window.get(win)

	CrashHandler = require('../crashHandler').load(win)
	BrandWidget = require('../brandWidget').load(win)
	PlanTab = require('./planTab').load(win)
	ProgNotesTab = require('./progNotesTab').load(win)
	AnalysisTab = require('./analysisTab').load(win)
	InfoTab = require('./infoTab').load(win)
	ClientAlerts = require('./clientAlerts').load(win)

	{FaIcon, renderName, renderRecordId, showWhen, showWhen3d, stripMetadata} = require('../utils').load(win)

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

				clientFile: null
				clientFileLock: null
				readOnlyData: null
				lockOperation: null

				progNoteTotal: null
				progNoteIndex: 10
				allProgNoteHeaders: null
				progNoteHistories: null
				progressEvents: null
				planTargetsById: Imm.Map()
				programsById: Imm.Map()
				metricsById: Imm.Map()
				attachmentHeaders: Imm.List()

				planTemplateHeaders: Imm.List()
				detailDefinitionGroups: Imm.List()

				loadErrorType: null
				loadErrorData: null
			}

		componentWillMount: ->
			# Set up secondPass vars
			@progNoteIndex = 0
			@progNoteTotal = 0
			@secondPassProgNoteHistories = Imm.List()

		init: ->
			@_renewAllData()

		deinit: (cb=(->)) ->
			@_killLocks cb

		suggestClose: ->
			@refs.ui.suggestClose()

		render: ->
			if @state.status isnt 'ready'
				return loadingSpinner({})

			clientName = renderName @state.clientFile.get('clientName')

			# Ensure revisions of each progNote are in chronological order (of creation)
			progNoteHistories = @state.progNoteHistories.map (history) ->
				return history.sortBy (revision) -> revision.get('timestamp')

			# Use programLinks to determine program membership(s)
			# TODO: Refactor to clientProgramsById for faster searching by ID
			clientPrograms = @state.clientFileProgramLinkHeaders.map (link) =>
				programId = link.get('programId')
				return @state.programsById.get programId

			clientHasPrograms = not clientPrograms.isEmpty()

			# Filter down to active global events that belong in this clientFile
			globalEvents = @state.globalEvents.filter (globalEvent) =>
				isActive = globalEvent.get('status') is 'default'
				originatesFromClient = globalEvent.get('clientFileId') is clientFileId

				programId = globalEvent.get('programId')
				hasNoProgram = not programId
				isInClientProgram = clientPrograms.contains @state.programsById.get(programId)

				return (isActive or originatesFromClient) and (hasNoProgram or isInClientProgram)

			# Map of attachments for easier access by progNoteId
			attachmentsByProgNoteId = @state.attachmentHeaders.groupBy (attachment) ->
				attachment.get('relatedProgNoteId')


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
				attachmentsByProgNoteId
				globalEvents
				alerts: @state.alerts

				closeWindow: @props.closeWindow
				setWindowTitle: @props.setWindowTitle
				updatePlan: @_updatePlan

				renewAllData: @_renewAllData
				secondPass: @_secondPass
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
			progNoteTotal = null
			progNoteHeaders = null
			allProgNoteHeaders = null
			progNoteHistories = null
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
			alertHeaders = null
			alerts = null
			detailDefinitionHeaders = null
			detailDefinitionGroups = null
			attachmentHeaders = null


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
					# load headers in parallel (TODO: confirm whether reading directories can cause EMFILE issues)
					Async.parallel [
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
							ActiveSession.persist.progNotes.list clientFileId, (err, results) =>
								if err
									cb err
									return

								# fast first pass
								if @state.status is "init"
									# need the count for fast second pass
									@progNoteTotal = results.size

									allProgNoteHeaders = results
									.sortBy (header) ->
										createdAt = header.get('backdate') or header.get('timestamp')
										return Moment createdAt, Persist.TimestampFormat

									progNoteHeaders = allProgNoteHeaders.reverse().slice(0, 10)
								else
									progNoteHeaders = results

								cb()

						(cb) =>
							ActiveSession.persist.progEvents.list clientFileId, (err, results) =>
								if err
									cb err
									return

								progEventHeaders = results
								cb()

						(cb) =>
							ActiveSession.persist.attachments.list clientFileId, (err, results) =>
								if err
									cb err
									return

								attachmentHeaders = results
								cb()

						(cb) =>
							ActiveSession.persist.globalEvents.list (err, results) =>
								if err
									cb err
									return

								globalEventHeaders = results
								cb()

						(cb) =>
							ActiveSession.persist.metrics.list (err, results) =>
								if err
									cb err
									return

								metricHeaders = results
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
							ActiveSession.persist.eventTypes.list (err, result) =>
								if err
									cb err
									return

								eventTypeHeaders = result
								cb()

						(cb) =>
							ActiveSession.persist.alerts.list clientFileId, (err, result) =>
								if err
									cb err
									return
								alertHeaders = result
								cb()

						(cb) =>
							ActiveSession.persist.planTemplates.list (err, result) =>
								if err
									cb err
									return

								planTemplateHeaders = result
								.filter (template) -> template.get('status') is 'default'
								cb()

					], (err) =>
						if err
							cb err
							return
						# headers loaded, carry on in series
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
					Async.map globalEventHeaders.toArray(), (globalEventHeader, cb) =>
						ActiveSession.persist.globalEvents.readLatestRevisions globalEventHeader.get('id'), 1, cb
					, (err, results) =>
						if err
							cb err
							return

						globalEvents = Imm.List(results).map (revisions) -> revisions.first()
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
					ActiveSession.persist.clientDetailDefinitionGroups.list (err, result) =>
						if err
							cb err
							return

						detailDefinitionHeaders = result
						cb()

				(cb) =>
					# Check to see whether detailGroups (from Config) have been created yet
					# make this dynamic, ie what if config is edited? add logic to handle this.
					if detailDefinitionHeaders.size > 0 or Config.clientDetailDefinitionGroups.size is 0
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

						clientFile
						allProgNoteHeaders
						progNoteHistories
						progressEvents
						attachmentHeaders
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

		_secondPass: (deadline) ->
			progNoteHistories = null

			if (deadline.timeRemaining() > 0 or deadline.didTimout) and (@progNoteIndex < @progNoteTotal)
				console.info "Second pass start..."

				# lets see what can we do in 100ms
				count = if deadline.didTimeout then 100 else 10

				progNoteHeaders = @state.allProgNoteHeaders.slice(@progNoteIndex, @progNoteIndex + count)
				@progNoteIndex += count

				Async.map progNoteHeaders.toArray(), (progNoteHeader, cb) =>
					ActiveSession.persist.progNotes.readRevisions clientFileId, progNoteHeader.get('id'), cb
				, (err, results) =>
					if err
						if err instanceof Persist.IOError
							console.error err
							@setState {loadErrorType: 'io-error'}
							return

						CrashHandler.handle err
						return

					if @progNoteIndex < @progNoteTotal
						# Add to temp store, run another batch
						@secondPassProgNoteHistories = @secondPassProgNoteHistories.concat results
						requestIdleCallback @_secondPass
					else
						console.info "Second pass complete!"
						# Temporary attempt at ensuring all progNotes loaded in are unique
						progNoteHistories = @state.progNoteHistories
						.concat @secondPassProgNoteHistories
						.toSet().toList()

						@setState {progNoteHistories}

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
									new Notification "#{clientName} file unlocked", {
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
			# TODO: Refactor these to be more consistent & performant

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

				'create:attachment': (newAttachment) =>
					return unless newAttachment.get('clientFileId') is clientFileId
					attachmentHeaders = @state.attachmentHeaders.push newAttachment
					@setState {attachmentHeaders}

				'createRevision:attachment': (newAttachmentRev) =>
					return unless newAttachmentRev.get('clientFileId') is clientFileId
					originalAttachment = @state.attachmentHeaders
					.find (attachment) -> attachment.get('id') is newAttachmentRev.get('id')
					.remove 'encodedData' # Should we keep this in memory, as a convenience?

					attachmentIndex = @state.attachmentHeaders.indexOf originalAttachment
					attachmentHeaders = @state.attachmentHeaders.set attachmentIndex, newAttachmentRev
					@setState {attachmentHeaders}

				'create:metric createRevision:metric': (metricDefinition) =>
					metricsById = @state.metricsById.set metricDefinition.get('id'), metricDefinition
					@setState {metricsById}

				'create:planTemplate': (newTemplate) =>
					planTemplateHeaders = @state.planTemplateHeaders.push newTemplate
					@setState {planTemplateHeaders}

				'createRevision:planTemplate': (newTemplateRev) =>
					originalTemplate = @state.planTemplateHeaders
					.find (template) -> template.get('id') is template.get('id')

					templateIndex = @state.planTemplateHeaders.indexOf originalTemplate
					planTemplateHeaders = @state.planTemplateHeaders.set templateIndex, newTemplateRev
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

				'createRevision:globalEvent': (newGlobalEventRev) =>
					originalGlobalEvent = @state.globalEvents
					.find (globalEvent) -> globalEvent.get('id') is newGlobalEventRev.get('id')

					globalEventIndex = @state.globalEvents.indexOf originalGlobalEvent
					globalEvents = @state.globalEvents.set globalEventIndex, newGlobalEventRev
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
						You have unsaved changes in #{Term 'client'} information for #{clientName}.
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

			# It's now OK to close the window
			@hasMounted = true

			# second pass at data load
			if @props.status is 'ready'
				requestIdleCallback @props.secondPass, timeout: 3000

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
					ReadOnlyNotice({data: @props.readOnlyData})
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
							'view plan'
							showWhen activeTabId is 'plan'
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
							showWhen3d activeTabId is 'progressNotes'
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
							programsById: @props.programsById
							attachmentsByProgNoteId: @props.attachmentsByProgNoteId

							hasChanges: @hasChanges
							onTabChange: @_changeTab

							renewAllData: @props.renewAllData

							isReadOnly
						})
					)
					R.div({
						className: [
							'view analysis'
							showWhen activeTabId is 'analysis'
						].join ' '
					},
						AnalysisTab.AnalysisView({
							ref: 'analysisTab'
							isVisible: activeTabId is 'analysis'
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
							'view info'
							showWhen activeTabId is 'info'
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
					@props.clientName
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
						name: "Information"
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


	LoadError = React.createFactory React.createClass
		displayName: 'LoadError'

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
