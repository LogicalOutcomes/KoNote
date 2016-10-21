# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

Fs = require 'fs'
Path = require 'path'
Assert = require 'assert'
Imm = require 'immutable'
Moment = require 'moment'
Async = require 'async'

Config = require '../config'
Term = require '../term'
Persist = require '../persist'

load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM
	{findDOMNode} = win.ReactDOM
	ReactDOMServer = win.ReactDOMServer

	CancelProgNoteDialog = require('./cancelProgNoteDialog').load(win)
	ColorKeyBubble = require('../colorKeyBubble').load(win)

	CrashHandler = require('../crashHandler').load(win)
	ExpandingTextArea = require('../expandingTextArea').load(win)
	MetricWidget = require('../metricWidget').load(win)
	OpenDialogLink = require('../openDialogLink').load(win)
	ProgEventsWidget = require('../progEventsWidget').load(win)
	ProgNoteDetailView = require('../progNoteDetailView').load(win)
	PrintButton = require('../printButton').load(win)
	WithTooltip = require('../withTooltip').load(win)

	{FaIcon, openWindow, renderLineBreaks, showWhen, formatTimestamp, renderName, makeMoment
	getUnitIndex, getPlanSectionIndex, getPlanTargetIndex} = require('../utils').load(win)


	ProgNotesTab = React.createFactory React.createClass
		displayName: 'ProgNotesView'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				editingProgNoteId: null
				attachment: null
				selectedItem: null
				backdate: ''
				transientData: null
				isLoading: null
				historyEntries: Imm.List()
			}

		componentWillReceiveProps: (nextProps) ->
			@_buildHistoryEntries(nextProps)

		componentDidMount: ->
			@_buildHistoryEntries()

			# TODO: Restore for lazyload feature
			# progNotesPane = $('.historyEntries')
			# progNotesPane.on 'scroll', =>
			# 	if @props.isLoading is false and @props.headerIndex < @props.progNoteTotal
			# 		if progNotesPane.scrollTop() + (progNotesPane.innerHeight() * 2) >= progNotesPane[0].scrollHeight
			# 			@props.renewAllData()

		hasChanges: ->
			@_transientDataHasChanges()

		_buildHistoryEntries: (nextProps) ->
			if nextProps?
				progNoteHistories = nextProps.progNoteHistories
				clientFileId = nextProps.clientFileId
			else
				progNoteHistories = @props.progNoteHistories
				clientFileId = @props.clientFileId

			historyEntries = null

			Async.series [
				(cb) =>
					Async.map progNoteHistories.toArray(), (progNoteHistory, cb) =>
						timestamp = progNoteHistory.last().get('backdate') or progNoteHistory.first().get('timestamp')
						progNoteId = progNoteHistory.last().get('id')
						attachmentFilename = null

						ActiveSession.persist.attachments.list clientFileId, progNoteId, (err, results) =>
							if err
								cb err
								return

							if results.size > 0
								attachmentFilename = {
									clientFileId
									progNoteId
									attachmentId: results.first().get('id')
									filename: results.first().get('filename')
								}

							entry = Imm.fromJS {
								type: 'progNote'
								id: progNoteId
								timestamp
								attachmentFilename
								data: progNoteHistory
							}

							cb null, entry

					, (err, results) ->
						if err
							cb err
							return

						historyEntries = Imm.List(results)
						cb()

			], (err) =>
				if err
					if err instanceof Persist.IOError
						console.error err
						Bootbox.alert """
							Please check your network connection and try again.
						"""
						return

					CrashHandler.handle err
					return

				@setState {historyEntries}

		render: ->
			historyEntries = @state.historyEntries

			transientData = @state.transientData
			hasChanges = @_transientDataHasChanges()
			isEditing = transientData?

			historyEntries = if isEditing
				# Only show the single progNote while editing
				Imm.List [
					historyEntries.find (entry) => entry.get('id') is transientData.getIn(['progNote', 'id'])
				]
			else
				# Display all progNotes, tack on any active globalEvents, and sort!
				historyEntries
				.concat(
					@props.globalEvents
					.filter (globalEvent) ->
						globalEvent.get('status') is 'default'
					.map (globalEvent) ->
						return Imm.fromJS {
							type: 'globalEvent'
							id: globalEvent.get('id')
							timestamp: globalEvent.get('startTimestamp')
							programId: globalEvent.get('programId')
							data: globalEvent
						}
				)
				.sortBy (entry) -> entry.get('timestamp')
				.reverse()

			hasEnoughData = (@props.progNoteHistories.size + @props.globalEvents.size) > 0


			return R.div({className: 'progNotesView'},
				R.div({className: 'panes'},
					R.section({className: 'leftPane'},

						(if hasEnoughData

							R.div({className: 'flexButtonToolbar'},
								R.button({
									className: [
										'saveButton'
										'collapsed' unless isEditing
									].join ' '
									onClick: @_saveTransientData
									disabled: not hasChanges
								},
									FaIcon('save')
									"Save #{Term 'Progress Note'}"
								)

								R.button({
									className: [
										'discardButton'
										'collapsed' unless isEditing
									].join ' '
									onClick: @_cancelRevisingProgNote
								},
									FaIcon('undo')
									"Discard"
								)

								R.button({
									className: [
										'newProgNoteButton'
										'collapsed' if isEditing
									].join ' '
									onClick: @_openNewProgNote
									disabled: @state.isLoading or @props.isReadOnly
								},
									FaIcon('file')
									"New #{Term 'Progress Note'}"
								)

								R.button({
									ref: 'addQuickNoteButton'
									className: [
										'addQuickNoteButton'
										'collapsed' if isEditing
									].join ' '
									onClick: @_openNewQuickNote
									disabled: @props.isReadOnly
								},
									FaIcon('plus')
									"Add #{Term 'Quick Note'}"
								)
							)

						else
							R.div({className: 'empty'},
								R.div({className: 'message'},
									"This #{Term 'client'} does not currently have any #{Term 'progress notes'}."
								)
								R.button({
									className: 'btn btn-primary btn-lg newProgNoteButton'
									onClick: @_openNewProgNote
									disabled: @state.isLoading or @props.isReadOnly
								},
									FaIcon 'file'
									"New #{Term 'progress note'}"
								)
								R.button({
									ref: 'addQuickNoteButton'
									className: 'btn btn-default btn-lg addQuickNoteButton'
									onClick: @_openNewQuickNote
									disabled: @props.isReadOnly
								},
									FaIcon 'plus'
									"Add #{Term 'quick note'}"
								)
							)
						)

						(unless historyEntries.isEmpty()
							R.div({className: 'progNotesList'},
								(historyEntries.map (entry) =>
									switch entry.get('type')
										when 'progNote'
											ProgNoteContainer({
												key: entry.get('id')

												progNoteHistory: entry.get('data')
												attachments: entry.get('attachmentFilename')
												eventTypes: @props.eventTypes
												clientFile: @props.clientFile

												progEvents: @props.progEvents
												globalEvents: @props.globalEvents
												programsById: @props.programsById

												isReadOnly: @props.isReadOnly

												setSelectedItem: @_setSelectedItem
												selectProgNote: @_selectProgNote
												selectedItem: @state.selectedItem

												transientData
												isEditing

												startRevisingProgNote: @_startRevisingProgNote
												cancelRevisingProgNote: @_cancelRevisingProgNote

												updatePlanTargetNotes: @_updatePlanTargetNotes
												updateBasicUnitNotes: @_updateBasicUnitNotes
												updateBasicMetric: @_updateBasicMetric
												updatePlanTargetMetric: @_updatePlanTargetMetric
												updateQuickNotes: @_updateQuickNotes
											})
										when 'globalEvent'
											GlobalEventView({
												key: entry.get('id')
												globalEvent: entry.get('data')
												programsById: @props.programsById
											})
										else
											throw new Error "Unknown historyEntry type #{entry.get('type')}"
								)
							)
						)
					)
					R.section({className: 'rightPane'},
						ProgNoteDetailView({
							item: @state.selectedItem
							progNoteHistories: @props.progNoteHistories
							progEvents: @props.progEvents
							eventTypes: @props.eventTypes
							metricsById: @props.metricsById
							programsById: @props.programsById
						})
					)
				)
			)

		_startRevisingProgNote: (progNote, progEvents) ->
			# Include transient and original data into generic store
			transientData = Imm.fromJS {
				progNote
				originalProgNote: progNote

				progEvents
				originalProgEvents: progEvents
				# TODO: Allow editing for globalEvents as well
			}

			@setState {transientData}

		_cancelRevisingProgNote: ->
			if @_transientDataHasChanges()
				return Bootbox.confirm "Discard all changes made to the #{Term 'progress note'}?", (ok) =>
					if ok then @_discardTransientData()

			@_discardTransientData()

		_discardTransientData: ->
			@setState {transientData: null}

		_transientDataHasChanges: ->
			transientData = @state.transientData
			return null unless transientData?

			originalProgNote = transientData.get('originalProgNote')
			progNote = transientData.get('progNote')
			progNoteHasChanges = not Imm.is progNote, originalProgNote

			originalProgEvents = transientData.get('originalProgEvents')
			progEvents = transientData.get('progEvents')
			progEventsHasChanges = not Imm.is progEvents, originalProgEvents

			# TODO: Compare globalEvents
			return progNoteHasChanges or progEventsHasChanges

		_updateBasicUnitNotes: (unitId, event) ->
			newNotes = event.target.value
			transientData = @state.transientData

			unitIndex = getUnitIndex transientData.get('progNote'), unitId

			@setState {
				transientData: transientData.setIn(
					[
						'progNote'
						'units', unitIndex
						'notes'
					]
					newNotes
				)
			}

		_updatePlanTargetNotes: (unitId, sectionId, targetId, event) ->
			newNotes = event.target.value

			transientData = @state.transientData
			progNote = transientData.get('progNote')

			unitIndex = getUnitIndex progNote, unitId
			sectionIndex = getPlanSectionIndex progNote, unitIndex, sectionId
			targetIndex = getPlanTargetIndex progNote, unitIndex, sectionIndex, targetId

			@setState {
				transientData: transientData.setIn(
					[
						'progNote'
						'units', unitIndex
						'sections', sectionIndex
						'targets', targetIndex
						'notes'
					]
					newNotes
				)
			}

		_updateQuickNotes: (event) ->
			newNotes = event.target.value

			@setState {
				transientData: @state.transientData.setIn ['progNote', 'notes'], newNotes
			}

		_isValidMetric: (value) -> value.match /^-?\d*\.?\d*$/

		_updatePlanTargetMetric: (unitId, sectionId, targetId, metricId, newMetricValue) ->
			return unless @_isValidMetric(newMetricValue)

			transientData = @state.transientData
			progNote = transientData.get('progNote')

			unitIndex = getUnitIndex progNote, unitId
			sectionIndex = getPlanSectionIndex progNote, unitIndex, sectionId
			targetIndex = getPlanTargetIndex progNote, unitIndex, sectionIndex, targetId

			metricIndex = progNote.getIn(
				[
					'units', unitIndex
					'sections', sectionIndex
					'targets', targetIndex,
					'metrics'
				]
			).findIndex (metric) =>
				return metric.get('id') is metricId

			@setState {
				transientData: transientData.setIn(
					[
						'progNote'
						'units', unitIndex
						'sections', sectionIndex
						'targets', targetIndex
						'metrics', metricIndex
						'value'
					]
					newMetricValue
				)
			}

		_updateBasicMetric: (unitId, metricId, newMetricValue) ->
			return unless @_isValidMetric(newMetricValue)

			transientData = @state.transientData
			progNote = transientData.get('progNote')

			unitIndex = getUnitIndex progNote, unitId

			metricIndex = progNote.getIn ['units', unitIndex, 'metrics']
			.findIndex (metric) =>
				return metric.get('id') is metricId

			@setState {
				transientData: transientData.setIn(
					[
						'progNote'
						'units', unitIndex
						'metrics', metricIndex
						'value'
					]
					newMetricValue
				)
			}

		_saveTransientData: ->
			revisedProgNote = @state.transientData.get('progNote')

			ActiveSession.persist.progNotes.createRevision revisedProgNote, (err, result) =>
				if err
					if err instanceof Persist.IOError
						Bootbox.alert """
							An error occurred.  Please check your network connection and try again.
						"""
						return

					CrashHandler.handle err
					return

				@_discardTransientData()
				return

		_checkUserProgram: (cb) ->
			# Skip if no clientProgram(s)
			if @props.clientPrograms.isEmpty()
				cb()
				return

			userProgramId = global.ActiveSession.programId

			# Skip if userProgram matches one of the clientPrograms
			matchingUserProgram = @props.clientPrograms.find (program) ->
				userProgramId is program.get('id')

			if matchingUserProgram
				cb()
				return

			clientName = renderName @props.clientFile.get('clientName')

			userProgramName = if userProgramId
				@props.programsById.getIn [userProgramId, 'name']
			else
				"(none)"

			# Build programDropdown markup
			programDropdown = ReactDOMServer.renderToString(
				R.select({
					id: 'programDropdown'
					className: 'form-control '
				},
					R.option({value: ''}, "Select a #{Term 'client'} #{Term 'program'}")
					(@props.clientPrograms.map (program) ->
						R.option({value: program.get('id')}, program.get('name'))
					)
				)
			)

			focusPopover = ->
				setTimeout (=>
					$popover = $('.popover textarea')[0]
					if $popover? then $popover.focus()
				), 500

			# Prompt user about temporarily overriding their program
			Bootbox.dialog {
				title: "Switch to #{Term 'client'} #{Term 'program'}?"
				message: """
					#{clientName} is not enrolled in your assigned #{Term 'program'}: "<b>#{userProgramName}</b>".
					<br><br>
					Override your assigned #{Term 'program'} below, or click "Ignore".
					<br><br>
					#{programDropdown}
				"""
				buttons: {
					cancel: {
						label: "Cancel"
						className: "btn-default"
						callback: =>
							Bootbox.hideAll()
					}
					ignore: {
						label: "Ignore"
						className: "btn-warning"
						callback: ->
							focusPopover()
							cb()
					}
					success: {
						label: "Override #{Term 'Program'}"
						className: "btn-success"
						callback: =>
							userProgramId = $('#programDropdown').val()

							if not userProgramId? or userProgramId.length is 0
								Bootbox.alert "No #{Term 'program'} was selected, please try again."
								return

							userProgram = @props.programsById.get userProgramId

							# Override the user's program
							global.ActiveSession.persist.eventBus.trigger 'override:userProgram', userProgram

							focusPopover()
							cb()
					}
				}
			}

		_checkPlanChanges: (cb) ->
			# Check for unsaved changes to the client plan
			if not @props.hasChanges()
				cb()
				return

			# Prompt user about unsaved changes
			Bootbox.dialog {
				title: "Unsaved Changes to #{Term 'Plan'}"
				message: """
					You have unsaved changes in the #{Term 'plan'} that will not be reflected in this
					#{Term 'progress note'}. How would you like to proceed?
				"""
				buttons: {
					default: {
						label: "Cancel"
						className: "btn-default"
						callback: =>
							Bootbox.hideAll()
					}
					danger: {
						label: "Ignore"
						className: "btn-danger"
						callback: -> cb()
					}
					success: {
						label: "View #{Term 'Plan'}"
						className: "btn-success"
						callback: =>
							Bootbox.hideAll()
							@props.onTabChange 'plan'
							return
					}
				}
			}


		_openNewProgNote: ->
			Async.series [
				@_checkPlanChanges
				@_checkUserProgram
				(cb) =>
					@setState {isLoading: true}

					# Cache data to global, so can access again from newProgNote window
					# Set up the dataStore if doesn't exist
					# Store property as clientFile ID to prevent confusion
					global.dataStore ?= {}

					# Only needs to pass latest revisions of each planTarget
					# In this case, index [0] is the latest revision
					planTargetsById = @props.planTargetsById.map (target) -> target.get('revisions').first()

					global.dataStore[@props.clientFileId] = {
						clientFile: @props.clientFile
						planTargetsById
						metricsById: @props.metricsById
						progNoteHistories: @props.progNoteHistories
						progEvents: @props.progEvents
						eventTypes: @props.eventTypes
						programsById: @props.programsById
						clientPrograms: @props.clientPrograms
					}

					openWindow {
						page: 'newProgNote'
						clientFileId: @props.clientFileId
					}

					global.ActiveSession.persist.eventBus.once 'newProgNotePage:loaded', cb

			], (err) =>
				@setState {isLoading: false}

				if err
					CrashHandler.handle err
					return

		_openNewQuickNote: ->
			Async.series [
				@_checkUserProgram
				@_toggleQuickNotePopover
			], (err) ->
				if err
					CrashHandler.handle err
					return

		_attach: ->
			# Configures hidden file inputs with custom attributes, and clicks it
			$nwbrowse = $('#nwBrowse')
			$nwbrowse
			.off()
			#.attr('accept', ".#{extension}")
			.on('change', (event) => @_encodeFile event.target.value)
			.click()

		_encodeFile: (file) ->
			if file
				filename = Path.basename file
				attachment = Fs.readFileSync(file)
				filesize = Buffer.byteLength(attachment, 'base64')
				if filesize < 1048576
					filesize = (filesize / 1024).toFixed() + " KB"
				else
					filesize = (filesize / 1048576).toFixed() + " MB"

				# convert to base64 encoded string
				encodedAttachment = new Buffer(attachment).toString 'base64'

				@setState {
					attachment: {
						encodedData: encodedAttachment
						filename: filename
					}
				}
				$('#attachmentArea').append filename + " (" + filesize + ")"
				#@_decodeFile encodedAttachment
			return

		_toggleQuickNotePopover: ->
			# TODO: Refactor to stateful React component

			quickNoteToggle = $(findDOMNode @refs.addQuickNoteButton)

			quickNoteToggle.popover {
				placement: 'bottom'
				html: true
				trigger: 'manual'
				content: '''
					<textarea class="form-control"></textarea>
					<div id="attachmentArea"></div>
					<div class="buttonBar form-inline">
						<label>Date: </label> <input type="text" class="form-control backdate date"></input>
						<button class="btn btn-default" id="attachBtn"><i class="fa fa-paperclip"></i> Attach</button>
						<button class="cancel btn btn-danger"><i class="fa fa-trash"></i> Discard</button>
						<button class="save btn btn-primary"><i class="fa fa-check"></i> Save</button>
						<input type="file" class="hidden" id="nwBrowse"></input>
					</div>
				'''
			}

			if quickNoteToggle.data('isVisible')
				quickNoteToggle.popover('hide')
				quickNoteToggle.data('isVisible', false)
			else
				quickNoteToggle.popover('show')
				quickNoteToggle.data('isVisible', true)

				attachFile = $('#attachBtn')
				attachFile.on 'click', (event) =>
					@_attach event
					attachFile.blur()

				popover = quickNoteToggle.siblings('.popover')

				popover.find('.save.btn').on 'click', (event) =>
					event.preventDefault()

					@_createQuickNote popover.find('textarea').val(), @state.backdate, @state.attachment, (err) =>

						if @state.attachment?
							# refresh if we have an attachment since it is not ready when create:prognote fires in
							# the parent. TODO: make this more elegant
							@_buildHistoryEntries()

						@setState {
							backdate: '',
							attachment: null
						}

						if err
							if err instanceof Persist.IOError
								Bootbox.alert """
									An error occurred.  Please check your network connection and try again.
								"""
								return

							CrashHandler.handle err
							return

						quickNoteToggle.popover('hide')
						quickNoteToggle.data('isVisible', false)

				popover.find('.backdate.date').datetimepicker({
					format: 'MMM-DD-YYYY h:mm A'
					defaultDate: Moment()
					maxDate: Moment()
					widgetPositioning: {
						vertical: 'bottom'
					}
				}).on 'dp.change', (e) =>
					if Moment(e.date).format('YYYY-MM-DD-HH') is Moment().format('YYYY-MM-DD-HH')
						@setState {backdate: ''}
					else
						@setState {backdate: Moment(e.date).format(Persist.TimestampFormat)}

				popover.find('.cancel.btn').on 'click', (event) =>
					event.preventDefault()
					@setState {
						backdate: '',
						attachment: null
					}
					quickNoteToggle.popover('hide')
					quickNoteToggle.data('isVisible', false)

				popover.find('textarea').focus()

				# Store quickNoteBeginTimestamp as class var, since it wont change
				@quickNoteBeginTimestamp = Moment().format(Persist.TimestampFormat)

		_createQuickNote: (notes, backdate, attachment, cb) ->
			unless notes
				Bootbox.alert "Cannot create an empty #{Term 'quick note'}."
				return

			quickNote = Imm.fromJS {
				type: 'basic'
				status: 'default'
				clientFileId: @props.clientFileId
				notes
				backdate
				authorProgramId: global.ActiveSession.programId or ''
				beginTimestamp: @quickNoteBeginTimestamp
			}

			# TODO: Async series
			global.ActiveSession.persist.progNotes.create quickNote, (err, result) =>
				if err
					cb err
					return

				unless attachment
					cb()
					return

				attachmentData = Imm.fromJS {
					filename: attachment.filename
					encodedData: attachment.encodedData
					clientFileId: @props.clientFileId
					progNoteId: result.get('id')
				}

				global.ActiveSession.persist.attachments.create attachmentData, (err) =>
					if err
						cb err
						return
					cb()

		_setSelectedItem: (selectedItem) ->
			@setState {selectedItem}

		_selectProgNote: (progNote) ->
			@_setSelectedItem Imm.fromJS {
				type: 'progNote'
				progNoteId: progNote.get('id')
			}


	ProgNoteContainer = React.createFactory React.createClass
		displayName: 'ProgNoteContainer'
		mixins: [React.addons.PureRenderMixin]

		render: ->
			{isEditing} = @props

			progNote = @props.progNoteHistory.last()
			progNoteId = progNote.get('id')

			firstProgNoteRev = @props.progNoteHistory.first()
			userProgramId = firstProgNoteRev.get('authorProgramId')
			userProgram = @props.programsById.get(userProgramId) or Imm.Map()

			# Filter out only events for this progNote
			progEvents = @props.progEvents.filter (progEvent) ->
				return progEvent.get('relatedProgNoteId') is progNote.get('id')

			globalEvents = @props.globalEvents.filter (globalEvent) ->
				return globalEvent.get('relatedProgNoteId') is progNoteId


			# TODO: Pass props down in a more efficient manner, maybe by grouping them together

			if progNote.get('status') is 'cancelled'
				return CancelledProgNoteView({
					progNoteHistory: @props.progNoteHistory
					progEvents
					globalEvents
					eventTypes: @props.eventTypes
					clientFile: @props.clientFile
					userProgram
					setSelectedItem: @props.setSelectedItem
					selectedItem: @props.selectedItem
					selectProgNote: @props.selectProgNote
					isReadOnly: @props.isReadOnly

					isEditing: @props.isEditing
					transientData: @props.transientData
					startRevisingProgNote: @props.startRevisingProgNote
					cancelRevisingProgNote: @props.cancelRevisingProgNote
					updateBasicUnitNotes: @props.updateBasicUnitNotes
					updatePlanTargetNotes: @props.updatePlanTargetNotes
					updatePlanTargetMetric: @props.updatePlanTargetMetric
					updateQuickNotes: @props.updateQuickNotes
					saveProgNoteRevision: @props.saveProgNoteRevision
				})

			Assert.equal progNote.get('status'), 'default'

			switch progNote.get('type')
				when 'basic'
					QuickNoteView({
						progNote
						progNoteHistory: @props.progNoteHistory
						attachments: @props.attachments
						userProgram
						clientFile: @props.clientFile
						selectedItem: @props.selectedItem
						setSelectedItem: @props.setSelectedItem
						selectProgNote: @props.selectProgNote
						isReadOnly: @props.isReadOnly

						isEditing
						transientData: @props.transientData
						startRevisingProgNote: @props.startRevisingProgNote
						cancelRevisingProgNote: @props.cancelRevisingProgNote
						updateQuickNotes: @props.updateQuickNotes
						saveProgNoteRevision: @props.saveProgNoteRevision
					})
				when 'full'
					ProgNoteView({
						progNote
						progNoteHistory: @props.progNoteHistory
						progEvents
						globalEvents
						userProgram
						eventTypes: @props.eventTypes
						clientFile: @props.clientFile
						setSelectedItem: @props.setSelectedItem
						selectProgNote: @props.selectProgNote
						setEditingProgNoteId: @props.setEditingProgNoteId
						updatePlanTargetNotes: @props.updatePlanTargetNotes
						selectedItem: @props.selectedItem
						isReadOnly: @props.isReadOnly

						isEditing
						transientData: @props.transientData
						startRevisingProgNote: @props.startRevisingProgNote
						cancelRevisingProgNote: @props.cancelRevisingProgNote
						updateBasicUnitNotes: @props.updateBasicUnitNotes
						updateBasicMetric: @props.updateBasicMetric
						updatePlanTargetMetric: @props.updatePlanTargetMetric
						saveProgNoteRevision: @props.saveProgNoteRevision
					})
				else
					throw new Error "unknown prognote type: #{progNote.get('type')}"


	QuickNoteView = React.createFactory React.createClass
		displayName: 'QuickNoteView'
		mixins: [React.addons.PureRenderMixin]

		render: ->
			isEditing = @props.isEditing

			progNote = if isEditing then @props.transientData.get('progNote') else @props.progNote

			if @props.attachments?
				attachmentText = " " + @props.attachments.get('filename')

			R.div({className: 'basic progNote'},
				EntryHeader({
					revisionHistory: @props.progNoteHistory
					userProgram: @props.userProgram
				})
				R.div({className: 'notes'},
					(if not isEditing and progNote.get('status') isnt 'cancelled'
						ProgNoteToolbar({
							isReadOnly: @props.isReadOnly
							progNote
							progNoteHistory: @props.progNoteHistory
							progEvents: @props.progEvents
							globalEvents: @props.globalEvents
							clientFile: @props.clientFile
							selectedItem: @props.selectedItem

							startRevisingProgNote: @props.startRevisingProgNote
							selectProgNote: @props.selectProgNote
						})
					)
					R.div({onClick: @_selectQuickNote},
						(if isEditing
							ExpandingTextArea({
								value: progNote.get('notes')
								onChange: @props.updateQuickNotes
							})
						else
							renderLineBreaks progNote.get('notes')
						)
					)
					(if attachmentText?
						R.a({
							className: 'attachment'
							onClick: @_openAttachment.bind null, @props.attachments
						},
							FaIcon(Path.extname attachmentText)
							attachmentText
						)
					)
				)
			)

		_openAttachment: (attachment) ->
			if attachment?
				clientFileId = attachment.get('clientFileId')
				progNoteId = attachment.get('progNoteId')
				attachmentId = attachment.get('attachmentId')

				global.ActiveSession.persist.attachments.readRevisions clientFileId, progNoteId, attachmentId, (err, object) ->
					if err
						if err instanceof Persist.IOError
							Bootbox.alert """
								An error occurred.  Please check your network connection and try again.
							"""
							return

						CrashHandler.handle err
						return

					encodedData = object.first().get('encodedData')
					filename = object.first().get('filename')
					if filename?
						# absolute path required for windows
						filepath = Path.join process.cwd(), Config.dataDirectory, '_tmp', filename
						file = new Buffer(encodedData, 'base64')
						# TODO cleanup file...
						Fs.writeFileSync filepath, file
						nw.Shell.openItem filepath

		_selectQuickNote: ->
			@props.setSelectedItem Imm.fromJS {
				type: 'quickNote'
				progNoteId: @props.progNote.get('id')
			}


	ProgNoteView = React.createFactory React.createClass
		displayName: 'ProgNoteView'
		mixins: [React.addons.PureRenderMixin]

		_filterEmptyValues: (progNote) ->
			progNoteUnits = progNote.get('units')
			.map (unit) ->
				if unit.get('type') is 'basic'
					# Strip empty metric values
					unitMetrics = unit.get('metrics').filterNot (metric) -> not metric.get('value')
					return unit.set('metrics', unitMetrics)

				else if unit.get('type') is 'plan'
					unitSections = unit.get('sections')
					.map (section) ->
						sectionTargets = section.get('targets')
						# Strip empty metric values
						.map (target) ->
							targetMetrics = target.get('metrics').filterNot (metric) ->
								return not metric.get('value')
							return target.set('metrics', targetMetrics)
						# Strip empty targets
						.filterNot (target) ->
							not target.get('notes') and target.get('metrics').isEmpty()

						return section.set('targets', sectionTargets)

					.filterNot (section) ->
						section.get('targets').isEmpty()

					return unit.set('sections', unitSections)

				else
					throw new Error "Unknown progNote unit type: #{unit.get('type')}"

			.filterNot (unit) ->
				# Finally, strip any empty 'basic' units, or 'plan' units with 0 sections
				if unit.get('type') is 'basic'
					return not unit.get('notes') and unit.get('metrics').isEmpty()
				else if unit.get('type') is 'plan'
					return unit.get('sections').isEmpty()
				else
					throw new Error "Unknown progNote unit type: #{unit.get('type')}"


			return progNote.set('units', progNoteUnits)

		render: ->
			{isEditing} = @props

			# Filter out any empty notes/metrics, unless we're editing
			progNote = if isEditing then @props.transientData.get('progNote') else @_filterEmptyValues(@props.progNote)

			R.div({className: 'full progNote'},
				EntryHeader({
					revisionHistory: @props.progNoteHistory
					userProgram: @props.userProgram
				})
				R.div({className: 'progNoteList'},
					(if not isEditing and progNote.get('status') isnt 'cancelled'
						ProgNoteToolbar({
							isReadOnly: @props.isReadOnly
							progNote: @props.progNote
							progNoteHistory: @props.progNoteHistory
							progEvents: @props.progEvents
							globalEvents: @props.globalEvents
							clientFile: @props.clientFile
							selectedItem: @props.selectedItem

							startRevisingProgNote: @props.startRevisingProgNote
							selectProgNote: @props.selectProgNote
						})
					)
					(progNote.get('units').map (unit) =>
						unitId = unit.get 'id'

						# TODO: Make these into components
						(switch unit.get('type')
							when 'basic'
								if unit.get('notes')
									R.div({
										className: [
											'basic unit'
											'selected' if @props.selectedItem? and @props.selectedItem.get('unitId') is unitId
										].join ' '
										key: unitId
										onClick: @_selectBasicUnit.bind null, unit
									},
										R.h3({}, unit.get('name'))
										R.div({className: 'notes'},
											(if isEditing
												ExpandingTextArea({
													value: unit.get('notes')
													onChange: @props.updateBasicUnitNotes.bind null, unitId
												})
											else
												if unit.get('notes').includes "***"
													R.span({className: 'starred'},
														renderLineBreaks unit.get('notes')
													)
												else
													renderLineBreaks unit.get('notes')
											)
										)

										(unless unit.get('metrics').isEmpty()
											R.div({className: 'metrics'},
												(unit.get('metrics').map (metric) =>
													MetricWidget({
														isEditable: isEditing
														key: metric.get('id')
														name: metric.get('name')
														definition: metric.get('definition')
														onFocus: @_selectBasicUnit.bind null, unit
														onChange: @props.updateBasicMetric.bind null, unitId, metricId
														value: metric.get('value')
													})
												)
											)
										)
									)
							when 'plan'
								R.div({
									className: 'plan unit'
									key: unitId
								},
									(unit.get('sections').map (section) =>
										sectionId = section.get('id')

										R.section({key: sectionId},
											R.h2({}, section.get('name'))
											R.div({
												className: [
													'empty'
													showWhen section.get('targets').isEmpty()
												].join ' '
											},
												"This #{Term 'section'} is empty because
												the #{Term 'client'} has no #{Term 'plan targets'}."
											)
											(section.get('targets').map (target) =>
												targetId = target.get('id')

												R.div({
													key: targetId
													className: [
														'target'
														'selected' if @props.selectedItem? and @props.selectedItem.get('targetId') is targetId
													].join ' '
													onClick: @_selectPlanSectionTarget.bind(null, unit, section, target)
												},
													R.h3({}, target.get('name'))
													R.div({className: "empty #{showWhen target.get('notes') is '' and not isEditing}"},
														'(blank)'
													)
													R.div({className: 'notes'},
														(if isEditing
															ExpandingTextArea({
																value: target.get('notes')
																onChange: @props.updatePlanTargetNotes.bind(
																	null,
																	unitId, sectionId, targetId
																)
															})
														else
															if target.get('notes').includes "***"
																R.span({className: 'starred'},
																	renderLineBreaks target.get('notes').replace(/\*\*\*/g, '')
																)
															else
																renderLineBreaks target.get('notes')
														)
													)
													R.div({className: 'metrics'},
														(target.get('metrics').map (metric) =>
															metricId = metric.get('id')

															MetricWidget({
																isEditable: isEditing
																tooltipViewport: '.progNotesList'
																onChange: @props.updatePlanTargetMetric.bind(
																	null,
																	unitId, sectionId, targetId, metricId
																)
																onFocus: @_selectPlanSectionTarget.bind(null, unit, section, target)
																key: metric.get('id')
																name: metric.get('name')
																definition: metric.get('definition')
																value: metric.get('value')
															})
														)
													)
												)
											)
										)
									)
								)
						)
					)

					(if progNote.get('summary')
						R.div({className: 'basic unit'},
							R.h3({}, "Shift Summary")
							R.div({className: 'notes'},
								renderLineBreaks progNote.get('summary')
							)
						)
					)

					(unless @props.progEvents.isEmpty()
						R.div({className: 'progEvents'}
							R.h3({}, Term 'Events')

							(@props.progEvents.map (progEvent) =>
								ProgEventsWidget({
									key: progEvent.get('id')
									format: 'large'
									data: progEvent
									eventTypes: @props.eventTypes
								})
							)
						)
					)
				)
			)

		_selectBasicUnit: (unit) ->
			@props.setSelectedItem Imm.fromJS {
				type: 'basicUnit'
				unitId: unit.get('id')
				unitName: unit.get('name')
				progNoteId: @props.progNote.get('id')
			}

		_selectPlanSectionTarget: (unit, section, target) ->
			@props.setSelectedItem Imm.fromJS {
				type: 'planSectionTarget'
				unitId: unit.get('id')
				sectionId: section.get('id')
				targetId: target.get('id')
				targetName: target.get('name')
				progNoteId: @props.progNote.get('id')
			}


	CancelledProgNoteView = React.createFactory React.createClass
		displayName: 'CancelledProgNoteView'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				isExpanded: false
			}

		render: ->
			# Here, we assume that the latest revision was the one that
			# changed the status.  This assumption may become invalid
			# when full prognote editing becomes supported.
			latestRev = @props.progNoteHistory.last()
			firstRev = @props.progNoteHistory.first()
			statusChangeRev = latestRev

			return R.div({className: 'cancelStub'},
				R.button({
					className: 'toggleDetails btn btn-xs btn-default'
					onClick: @_toggleDetails
				},
					R.span({className: "#{showWhen not @state.isExpanded}"},
						FaIcon 'chevron-down'
						" Show details"
					)
					R.span({className: "#{showWhen @state.isExpanded}"},
						FaIcon 'chevron-up'
						" Hide details"
					)
				)

				R.h3({},
					"Cancelled: "
					formatTimestamp(firstRev.get('backdate') or firstRev.get('timestamp'))
					" (late entry)" if firstRev.get('backdate')
				),

				R.div({className: "details #{showWhen @state.isExpanded}"},
					R.h4({},
						"Cancelled by "
						statusChangeRev.get('author')
						" on "
						formatTimestamp statusChangeRev.get('timestamp')
					),
					R.h4({}, "Reason for cancellation:")
					R.div({className: 'reason'},
						renderLineBreaks latestRev.get('statusReason')
					)

					switch latestRev.get('type')
						when 'basic'
							QuickNoteView({
								progNote: @props.progNoteHistory.last()
								progNoteHistory: @props.progNoteHistory
								clientFile: @props.clientFile
								selectedItem: @props.selectedItem
								selectProgNote: @props.selectProgNote
								userProgram: @props.userProgram
								isReadOnly: true

								isEditing: @props.isEditing
								transientData: @props.transientData
								startRevisingProgNote: @props.startRevisingProgNote
								cancelRevisingProgNote: @props.cancelRevisingProgNote
								updateQuickNotes: @props.updateQuickNotes
								saveProgNoteRevision: @props.saveProgNoteRevision
							})
						when 'full'
							ProgNoteView({
								progNote: @props.progNoteHistory.last()
								progNoteHistory: @props.progNoteHistory
								progEvents: @props.progEvents
								globalEvents: @props.globalEvents
								eventTypes: @props.eventTypes
								userProgram: @props.userProgram
								clientFile: @props.clientFile
								setSelectedItem: @props.setSelectedItem
								selectedItem: @props.selectedItem
								selectProgNote: @props.selectProgNote
								isReadOnly: true

								isEditing: @props.isEditing
								transientData: @props.transientData
								startRevisingProgNote: @props.startRevisingProgNote
								cancelRevisingProgNote: @props.cancelRevisingProgNote
								updatePlanTargetNotes: @props.updatePlanTargetNotes
								updatePlanTargetMetric: @props.updatePlanTargetMetric
								saveProgNoteRevision: @props.saveProgNoteRevision
							})
						else
							throw new Error "unknown prognote type: #{progNote.get('type')}"
				)
			)

		_toggleDetails: (event) ->
			@setState (s) -> {isExpanded: not s.isExpanded}


	EntryHeader = React.createFactory React.createClass
		displayName: 'EntryHeader'
		mixins: [React.addons.PureRenderMixin]

		render: ->
			{userProgram, revisionHistory} = @props

			hasRevisions = revisionHistory.size > 1
			numberOfRevisions = revisionHistory.size - 1

			firstRevision = revisionHistory.first() # Use original revision's data
			timestamp = (
				firstRevision.get('startTimestamp') or
				firstRevision.get('backdate') or
				firstRevision.get('timestamp')
			)

			R.div({className: 'entryHeader'},
				R.div({className: 'timestamp'},
					ColorKeyBubble({
						colorKeyHex: userProgram.get('colorKeyHex')
						popover: {
							title: userProgram.get('name')
							content: userProgram.get('description')
							placement: 'left'
						}
					})
					formatTimestamp(timestamp, @props.dateFormat)
					" (late entry)" if firstRevision.get('backdate')
				)
				R.div({className: 'author'},
					' by '
					firstRevision.get('author')
				)
			)

	ProgNoteToolbar = (props) ->
		{
			isReadOnly
			progNote
			progNoteHistory
			progEvents
			globalEvents
			clientFile
			selectedItem

			startRevisingProgNote
			selectProgNote
		} = props

		selectedItemIsProgNote = selectedItem? and selectedItem.get('progNoteId') is progNote.get('id')
		userIsAuthor = progNote.get('author') is global.ActiveSession.userName

		isViewingRevisions = selectedItemIsProgNote and selectedItem.get('type') is 'progNote'
		hasRevisions = progNoteHistory.size > 1
		numberOfRevisions = progNoteHistory.size - 1
		hasMultipleRevisions = numberOfRevisions > 1

		R.div({
			className: "progNoteToolbar #{if isViewingRevisions then 'active' else ''}"
		},
			R.div({className: "revisions #{showWhen hasRevisions}"},
				R.a({
					className: 'selectProgNoteButton'
					onClick: selectProgNote.bind null, progNote
				},
					"#{numberOfRevisions} revision#{if hasMultipleRevisions then 's' else ''}"
				)
			)
			R.div({className: 'actions'},
				PrintButton({
					dataSet: [
						{
							format: 'progNote'
							data: progNote
							progEvents
							clientFile
						}
					]
					isVisible: true
					iconOnly: true
					tooltip: {show: true}
				})
				(if userIsAuthor
					R.a({
						className: "editNote #{showWhen not isReadOnly}"
						onClick: startRevisingProgNote.bind null, progNote, progEvents
					},
						"Edit"
					)
				)
				OpenDialogLink({
					className: "cancelNote #{showWhen not isReadOnly}"
					dialog: CancelProgNoteDialog
					progNote
					progEvents
					globalEvents
				},
					R.a({}, "Cancel")
				)
			)
		)


	GlobalEventView = React.createFactory React.createClass
		displayName: 'GlobalEventView'
		mixins: [React.addons.PureRenderMixin]

		render: ->
			{globalEvent} = @props
			programId = globalEvent.get('programId')

			program = @props.programsById.get(programId) or Imm.Map()
			timestamp = globalEvent.get('backdate') or globalEvent.get('timestamp')

			startTimestamp = makeMoment globalEvent.get('startTimestamp')
			endTimestamp = makeMoment globalEvent.get('endTimestamp')

			# A full day is 12:00AM to 11:59PM
			isFullDay = (
				startTimestamp.isSame(startTimestamp.startOf 'day') and
				endTimestamp.isSame(endTimestamp.endOf 'day')
			)

			return R.div({className: 'globalEventView'},
				EntryHeader({
					revisionHistory: Imm.List [globalEvent]
					userProgram: program
					dateFormat: Config.dateFormat if isFullDay
				})
				R.h3({},
					FaIcon('globe')
					"Global Event: "
					globalEvent.get('title')
				)
				(if globalEvent.get('description')
					R.p({}, globalEvent.get('description'))
				)
				(if globalEvent.get('endTimestamp') and not isFullDay
					R.p({},
						"From: "
						formatTimestamp globalEvent.get('startTimestamp')
						" until "
						formatTimestamp globalEvent.get('endTimestamp')
					)
				)
				R.p({},
					"Reported: "
					formatTimestamp timestamp
				)
			)


	return ProgNotesTab

module.exports = {load}
