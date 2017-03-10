# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Client file view for displaying, searching, and updating progress notes

Fs = require 'fs'
Path = require 'path'
Assert = require 'assert'
Imm = require 'immutable'
Moment = require 'moment'
Async = require 'async'
_ = require 'underscore'

Config = require '../config'
Term = require '../term'
Persist = require '../persist'

dataTypeOptions = Imm.fromJS [
	# {name: 'Progress Notes', id: 'progNotes'}
	# {name: 'Targets', id: 'targets'}
	{name: 'Events', id: 'events'}
]


load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM
	{findDOMNode} = win.ReactDOM
	ReactDOMServer = win.ReactDOMServer
	Mark = win.Mark
	B = require('../utils/reactBootstrap').load(win, 'DropdownButton', 'MenuItem')

	CancelProgNoteDialog = require('./cancelProgNoteDialog').load(win)
	ColorKeyBubble = require('../colorKeyBubble').load(win)

	CrashHandler = require('../crashHandler').load(win)
	ExpandingTextArea = require('../expandingTextArea').load(win)
	MetricWidget = require('../metricWidget').load(win)
	ProgEventWidget = require('../progEventWidget').load(win)
	OpenDialogLink = require('../openDialogLink').load(win)
	ProgNoteDetailView = require('../progNoteDetailView').load(win)
	EntryDateNavigator = require('./entryDateNavigator').load(win)
	PrintButton = require('../printButton').load(win)
	WithTooltip = require('../withTooltip').load(win)
	FilterBar = require('./filterBar').load(win)

	{
		FaIcon, openWindow, renderLineBreaks, showWhen, formatTimestamp, renderName, makeMoment
		getUnitIndex, getPlanSectionIndex, getPlanTargetIndex, blockedExtensions, stripMetadata, scrollToElement
	} = require('../utils').load(win)

	# List of fields we exclude from keyword search
	excludedSearchFields = Imm.fromJS [
		'id', 'revisionId', 'templateId', 'typeId', 'relatedProgNoteId', 'programId'
		'relatedProgEventId', 'authorProgramId', 'clientFileId'
		'timestamp', 'backdate', 'startTimestamp', 'endTimestamp'
		'type', 'entryType', 'status', 'definition'
		# 'filteredProgNote' and {entryType: globalEvent} used instead
		'progNoteHistory', 'globalEvents'
	]


	ProgNotesTab = React.createFactory React.createClass
		displayName: 'ProgNotesTab'
		mixins: [React.addons.PureRenderMixin]
		# TODO: propTypes

		hasChanges: ->
			@refs.ui.hasChanges()

		_toProgNoteHistoryEntry: (progNoteHistory) ->
			latestRevision = progNoteHistory.last()
			firstRevision = progNoteHistory.first()

			# We pass down a pre-filtered version of the progNote
			# because the search-by-keyword feature relies on this data
			filteredProgNote = filterEmptyProgNoteValues(latestRevision)

			# Revisions all have same 'id', just different revisionIds
			progNoteId = firstRevision.get('id')
			programId = firstRevision.get('authorProgramId')
			timestamp = latestRevision.get('backdate') or firstRevision.get('timestamp')

			# Mix in all other related data from clientFile's other collections
			progEvents = @props.progEvents.filter (progEvent) ->
				return progEvent.get('relatedProgNoteId') is progNoteId

			# progNote still gets any cancelled globalEvents
			globalEvents = @props.globalEvents.filter (globalEvent) ->
				return globalEvent.get('relatedProgNoteId') is progNoteId

			attachments = @props.attachmentsByProgNoteId.get(progNoteId) or Imm.List()

			return Imm.Map {
				entryType: 'progNote'
				id: progNoteId
				programId
				timestamp
				progNoteHistory
				filteredProgNote
				progEvents
				globalEvents
				attachments
			}

		_toGlobalEventEntry: (globalEvent) ->
			timestamp = globalEvent.get('startTimestamp') # Order by startTimestamp

			return Imm.Map {
				entryType: 'globalEvent'
				id: globalEvent.get('id')
				programId: globalEvent.get('programId')
				timestamp
				globalEvent
			}

		render: ->
			progNoteEntries = @props.progNoteHistories.map @_toProgNoteHistoryEntry

			globalEventEntries = @props.globalEvents
			.filter (e) -> e.get('status') is 'default'
			.map @_toGlobalEventEntry

			historyEntries = progNoteEntries
			.concat globalEventEntries
			.sortBy (entry) -> entry.get('timestamp')
			.reverse()

			props = _.extend {}, @props, {
				ref: 'ui'
				historyEntries
			}

			return ProgNotesTabUi(props)


	ProgNotesTabUi = React.createFactory React.createClass
		displayName: 'ProgNotesTabUi'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				editingProgNoteId: null
				attachment: null
				selectedItem: null
				backdate: ''
				transientData: null
				isLoading: null
				isFiltering: null

				searchQuery: ''
				programIdFilter: null
				dataTypeFilter: null
			}

		hasChanges: ->
			@_transientDataHasChanges()

		render: ->
			{transientData} = @state

			hasChanges = @hasChanges()
			hasEnoughData = @props.historyEntries.size > 0
			isEditing = transientData?

			# Only show the single progNote while editing
			historyEntries = if not isEditing then @props.historyEntries else Imm.List [
				@props.historyEntries.find (entry) ->
					entry.get('id') is transientData.getIn(['progNote', 'id'])
			]


			####### Filtering / Search Logic #######

			if @state.isFiltering
				# TODO: Make this filtering faster

				# By program?
				if @state.programIdFilter
					historyEntries = historyEntries.filter (e) => e.get('programId') is @state.programIdFilter

				# By type of progNote?
				if @state.dataTypeFilter in ['progNotes', 'targets']
					historyEntries = historyEntries.filter (e) => e.get('entryType') is 'progNote'

				# by event without a query (suppress notes)
				if @state.dataTypeFilter is 'events'
					historyEntries = historyEntries.filter (e) => e.get('entryType') is 'globalEvent' or not e.get('progEvents').isEmpty()

					# When searching 'targets', only check 'full' progNotes
					# TODO: Restore this dataType at some point
					# if @state.dataTypeFilter is 'targets'
					# 	historyEntries = historyEntries.filter (e) => e.getIn(['filteredProgNote', 'type']) is 'full'

				# By search query? Pass dataTypeFilter for conditional property checks
				if @state.searchQuery.trim().length > 0
					historyEntries = @_filterEntries(historyEntries, @state.dataTypeFilter)


			return R.div({className: 'progNotesView'},
				R.div({className: 'panes'},
					R.section({className: 'leftPane'},

						(if hasEnoughData
							# TODO: Make component
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

								R.button({
									ref: 'openFilterBarButton'
									className: [
										'openFilterBarButton'
										'collapsed' if isEditing or @state.isFiltering
									].join ' '
									onClick: @_toggleIsFiltering
								},
									FaIcon('search')
								)
							)

						else
							R.div({className: 'empty'},
								R.div({className: 'message'},
									R.div({},
										"This #{Term 'client'} does not currently have any #{Term 'progress notes'}."
									)
									R.button({
										className: 'btn btn-primary btn-lg newProgNoteButton'
										onClick: @_openNewProgNote
										disabled: @state.isLoading or @props.isReadOnly
									},
										FaIcon('file')
										"New #{Term 'progress note'}"
									)
									R.button({
										ref: 'addQuickNoteButton'
										className: 'btn btn-default btn-lg addQuickNoteButton'
										onClick: @_openNewQuickNote
										disabled: @props.isReadOnly
									},
										FaIcon('plus')
										"Add #{Term 'quick note'}"
									)
								)
							)
						)

						(if @state.isFiltering and not isEditing
							FilterBar({
								ref: 'filterBar'
								historyEntries
								programIdFilter: @state.programIdFilter
								dataTypeFilter: @state.dataTypeFilter
								programsById: @props.programsById
								dataTypeOptions

								onClose: @_toggleIsFiltering
								onUpdateSearchQuery: @_updateSearchQuery
								onSelectProgramId: @_updateProgramIdFilter
								onSelectDataType: @_updateDataTypeFilter
							})
						)

						# TODO: Make component
						R.div({
							className: [
								'empty'
								showWhen @state.isFiltering and historyEntries.isEmpty()
							].join ' '
						},
							R.div({className: 'message animated fadeIn'},
								R.div({},
									"No results found"

									(if @state.dataTypeFilter
										R.span({},
											" in "
											R.strong({},
												dataTypeOptions.find((t) => t.get('id') is @state.dataTypeFilter).get('name')
											)
										)
									)
								)
								(if @state.searchQuery.trim().length > 0
									R.div({},
										"matching: \""
										R.strong({}, @state.searchQuery)
										"\""
									)
								)
								(if @state.programIdFilter
									R.div({},
										"for: "

										R.strong({},
											@props.programsById.getIn [@state.programIdFilter, 'name']
										)
										ColorKeyBubble({
											colorKeyHex: @props.programsById.getIn [@state.programIdFilter, 'colorKeyHex']
										})
									)
								)
								R.div({},
									R.button({
										id: 'resetFilterButton'
										className: 'btn btn-link'
										onClick: => @refs.filterBar.clear()
									},
										FaIcon('refresh')
										"Reset"
									)
								)
							)
						)

						# Apply selectedItem styles as inline <style>
						(if @state.selectedItem?
							InlineSelectedItemStyles({
								selectedItem: @state.selectedItem
							})
						)

						EntriesListView({
							ref: 'entriesListView'
							historyEntries
							entryIds: historyEntries.map (e) -> e.get('id')
							transientData

							eventTypes: @props.eventTypes
							clientFile: @props.clientFile
							programsById: @props.programsById
							planTargetsById: @props.planTargetsById

							dataTypeFilter: @state.dataTypeFilter
							searchQuery: @state.searchQuery
							programIdFilter: @state.programIdFilter

							isFiltering: @state.isFiltering
							isReadOnly: @props.isReadOnly
							isEditing

							setSelectedItem: @_setSelectedItem
							selectProgNote: @_selectProgNote
							startRevisingProgNote: @_startRevisingProgNote
							cancelRevisingProgNote: @_cancelRevisingProgNote

							updatePlanTargetNotes: @_updatePlanTargetNotes
							updateBasicUnitNotes: @_updateBasicUnitNotes
							updateBasicMetric: @_updateBasicMetric
							updatePlanTargetMetric: @_updatePlanTargetMetric
							updateProgEvent: @_updateProgEvent
							updateQuickNotes: @_updateQuickNotes
						})
					)
					R.section({className: 'rightPane'},
						ProgNoteDetailView({
							ref: 'progNoteDetailView'
							isFiltering: @state.isFiltering
							searchQuery: @state.searchQuery
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

		_updateProgEvent: (index, updatedProgEvent) ->
			transientData = @state.transientData.setIn ['progEvents', index], updatedProgEvent
			@setState {transientData}

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
			{progNote, progEvents, originalProgNote, originalProgEvents} = @state.transientData.toObject()

			# Any progEvents modified?
			revisedProgEvents = progEvents.filter (progEvent, index) ->
				not Imm.is progEvent, originalProgEvents.get(index)

			# Only save modified progNotes/progEvents
			Async.series [
				(cb) ->
					return cb() if Imm.is originalProgNote, progNote
					ActiveSession.persist.progNotes.createRevision progNote, cb

				(cb) ->
					return cb() if revisedProgEvents.isEmpty()
					Async.map revisedProgEvents, ActiveSession.persist.progEvents.createRevision, cb

			], (err) =>
				if err
					if err instanceof Persist.IOError
						Bootbox.alert """
							An error occurred.  Please check your network connection and try again.
						"""
						return

					CrashHandler.handle err
					return

				@_discardTransientData()

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

					openWindow {page: 'newProgNote', clientFileId: @props.clientFileId}, (newProgNoteWindow) =>
						# prevent window from closing before its ready
						# todo a more elegant way to do this?
						newProgNoteWindow.on 'close', =>
							newProgNoteWindow = null

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
			return unless file

			# clear input value so onchange can still fire if user tries same file again
			$('#nwBrowse').val(null)

			filename = Path.basename file
			fileExtension = (Path.extname file).toLowerCase()

			if blockedExtensions.indexOf(fileExtension) > -1
				Bootbox.alert {
					title: "Warning: File Blocked"
					message: "#{filename} is potentially unsafe and cannot be attached."
				}
				return

			attachment = Fs.readFileSync(file)
			filesize = Buffer.byteLength(attachment, 'base64')

			if filesize < 1048576
				filesize = (filesize / 1024).toFixed() + " KB"
			else
				filesize = (filesize / 1048576).toFixed() + " MB"

			# Convert to base64 encoded string
			encodedAttachment = new Buffer(attachment).toString 'base64'

			@setState {
				attachment: {
					encodedData: encodedAttachment
					filename: filename
				}
			}

			# TODO: Append for when multiple attachments allowed (#787)
			$('#attachmentArea').html filename + " (" + filesize + ") <i class='fa fa-times' id='removeBtn'></i>"

			removeFile = $('#removeBtn')
			removeFile.on 'click', (event) =>
				$('#attachmentArea').html ''
				@setState {attachment: null}

		_toggleQuickNotePopover: ->
			# TODO: Refactor to stateful React component

			quickNoteToggle = $(findDOMNode @refs.addQuickNoteButton)

			quickNoteToggle.popover {
				placement: 'bottom'
				html: true
				trigger: 'manual'
				content: '''
					<textarea class="form-control"></textarea>
					<div id="attachmentArea" style="padding-top:10px; color:#3176aa;"></div>
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
					status: 'default'
					filename: attachment.filename
					encodedData: attachment.encodedData
					clientFileId: @props.clientFileId
					relatedProgNoteId: result.get('id')
				}

				global.ActiveSession.persist.attachments.create attachmentData, cb

		_setSelectedItem: (selectedItem) ->
			@setState {selectedItem}

		_selectProgNote: (progNote) ->
			@_setSelectedItem Imm.fromJS {
				type: 'progNote'
				progNoteId: progNote.get('id')
			}

		_filterEntries: (entries, dataTypeFilter) ->
			if @state.searchQuery.trim().length is 0
				return entries

			# Split into query parts
			queryParts = Imm.fromJS(@state.searchQuery.split(' ')).map (p) -> p.toLowerCase()

			containsSearchQuery = (data) ->

				if dataTypeFilter
					# Only search through 'progNote' types for progNotes and targets
					if dataTypeFilter in ['progNotes', 'targets'] and data.has('entryType') and data.get('entryType') isnt 'progNote'
						return false

					# For 'targets', favour 'filteredProgNote' with 'type: full' - since it only contains targets with data
					# TODO: Restore this dataType at some point
					# else if dataTypeFilter is 'targets'
					# 	data = data.get('filteredProgNote') or data

					else if dataTypeFilter is 'events'
						# Ignore progNote entries without progEvents
						if data.has('entryType') and data.get('entryType') isnt 'globalEvent' and data.get('progEvents').isEmpty()
							return false
						# Favor 'progEvents' in progNote entries
						else
							data = data.get('progEvents') or data


				return data.some (value, property) ->
					# Skip excluded field
					if excludedSearchFields.includes property
						return false

					# Run all keywords against string contents
					if typeof value is 'string'
						value = value.toLowerCase()
						includesAllParts = queryParts.every (part) -> value.includes(part)
						# if includesAllParts then console.log "Match:", "#{property}:", value
						return includesAllParts

					# When not a string, it must be an Imm.List / Map
					# so we'll loop through this same method on it
					return containsSearchQuery(value)


			# Only keep entries that contain all query parts
			return entries.filter containsSearchQuery

		_updateSearchQuery: (searchQuery) ->
			@setState {searchQuery}

		_toggleIsFiltering: ->
			isFiltering = not @state.isFiltering

			# Clear filter values when toggling off filterBar
			if not isFiltering
				@setState {
					isFiltering
					searchQuery: ''
					dataTypeFilter: null
					programIdFilter: null
				}
				return

			@setState {isFiltering}

		_updateProgramIdFilter: (programIdFilter) ->
			@setState {programIdFilter}

		_updateDataTypeFilter: (dataTypeFilter) ->
			@setState {dataTypeFilter}


	EntriesListView = React.createFactory React.createClass
		displayName: 'EntriesListView'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: -> {
			historyCount: 10
			filterCount: 10
		}

		componentDidMount: ->
			# Watch scroll for infinite scroll behaviour, throttle to 1call/per/150ms
			@_watchUnlimitedScroll = _.throttle(@_watchUnlimitedScroll, 150)

			@entriesListView = $(findDOMNode @)
			@entriesListView.on 'scroll', @_watchUnlimitedScroll

			# Custom positioning logic to have EntryDateNavigator hug this.bottom-right
			@entryDateNavigator = $(findDOMNode @refs.entryDateNavigator)

			# Set initial position, and listen for window resize
			@rightPane = $('.rightPane')[0] # Ref not available here, maybe get from this upstream?
			@_setNavigatorRightOffset()

			$(win).on 'resize', @_setNavigatorRightOffset

		componentDidUpdate: (oldProps, oldState) ->
			# Update highlighting when anything changes while searching
			# TODO: Maybe wrap component with this logic; allow state to change unimpeded
			if @props.isFiltering

				filterParametersChanged = (
					@props.searchQuery isnt oldProps.searchQuery or
					@props.dataTypeFilter isnt oldProps.dataTypeFilter or
					@props.programIdFilter isnt oldProps.programIdFilter
				)

				# Reset filterCount and scroll to top anytime filter parameters change
				if filterParametersChanged
					@setState @getInitialState, @_resetScroll


				if @props.searchQuery

					if @state.filterCount > oldState.filterCount
						# Only highlight new entries added from unlimited-scroll
						newEntriesCount = @state.filterCount - oldState.filterCount

						entryNodes = @props.entryIds
						.slice 0, @state.filterCount
						.takeLast newEntriesCount
						.map (id) -> win.document.getElementById(id)
						.toArray()

						new Mark(entryNodes).mark(@props.searchQuery)

					else
						@_redrawSearchHighlighting()

			# Toggle FilterBar, resets selectedItem
			if @props.isFiltering isnt oldProps.isFiltering
				if @props.isFiltering
					# Reset filterCount when FilterBar opens
					@setState {filterCount: 10}
				else
					# Clear search highlighting when FilterBar closes
					@_redrawSearchHighlighting()

				@props.setSelectedItem(null)

			# Reset scroll when opens edit view for progNote
			if @props.isEditing isnt oldProps.isEditing and @props.isEditing
				@_resetScroll()

		componentWillUnmount: ->
			@entriesListView.off 'scroll', @_watchUnlimitedScroll
			$(win.document).off 'resize', @_updateNavigatorPosition

		_watchUnlimitedScroll: ->
			# Skip if we're scrolling via EntryDateNavigator, entry count is already set
			return if @isAutoScrolling

			# Detect if we've reached the lower threshold to trigger update
			if @entriesListView.scrollTop() + (@entriesListView.innerHeight() *2) >= @entriesListView[0].scrollHeight

				# Count is contextual to complete history, or filtered entries
				countType = if @props.isFiltering then 'filterCount' else 'historyCount'

				# Disregard if nothing left to load into the count
				return if @state[countType] >= @props.historyEntries.size

				# Update UI with +10 to entry count
				nextState = {}
				nextState[countType] = @state[countType] + 10
				@setState(nextState)

		_setNavigatorRightOffset: ->
			# Add rightPane's width to navigator's initial (css) right positioning
			# TODO: Can we use new chrome 'sticky' instead? Sometimes doesn't show on HCR
			right = if @rightPane? then @rightPane.offsetWidth else 0
			@entryDateNavigator.css {right}

		_scrollToEntryDate: (date, cb=(->)) ->
			# TODO: Have moment objs already pre-built in historyEntries
			entry = @props.historyEntries.find (e) ->
				timestamp = makeMoment e.get('timestamp')
				return date.isSame timestamp, 'day'

			if not entry?
				console.warn "Cancelled scroll, could not find #{date.toDate()} in historyEntries"
				cb()
				return

			# Should we supplement filter/historyCount first?
			countType = if @props.isFiltering then 'filterCount' else 'historyCount'
			index = @props.historyEntries.indexOf entry
			requiresMoreEntries = @state[countType] - 1 < index


			Async.series [
				(cb) =>
					return cb() unless requiresMoreEntries

					# Provide 10 extra entries, so destinationEntry appears at top
					# Set the new count (whichever type is pertinent), and *then* scroll to the entry
					newState = {}
					newState[countType] = (index + 1) + 10
					@setState newState, cb

				(cb) =>
					# Scroll to latest entry matching date
					$entriesListView = findDOMNode(@)
					$element = win.document.getElementById "entry-#{entry.get('id')}"

					@isAutoScrolling = true # Temporarily block scroll listener(s)
					scrollToElement $entriesListView, $element, 1000, 'easeInOutQuad', cb

				(cb) =>
					@isAutoScrolling = false

					# Scroll is completed, briefly highlight/animate any entries with matching date
					selectedMoment = makeMoment entry.get('timestamp')

					entryIdsToFlash = @props.historyEntries
					.filter (e) ->
						timestamp = makeMoment e.get('timestamp')
						return selectedMoment.isSame makeMoment(timestamp), 'day'
					.map (e) -> '#entry-' + e.get('id')
					.toArray()
					.join ', '

					$(entryIdsToFlash).addClass 'flashDestination'
					setTimeout(->
						$(entryIdsToFlash).removeClass 'flashDestination'
					, 2500)

					cb()

			], cb

		_resetScroll: ->
			findDOMNode(@).scrollTop = 0

		_redrawSearchHighlighting: ->
			# Performs a complete (expensive) mark/unmark of the entire EntriesListView
			entriesHighlighting = new Mark findDOMNode @refs.entriesListView

			if @props.isFiltering
				entriesHighlighting.unmark().mark(@props.searchQuery)
			else
				entriesHighlighting.unmark()

		render: ->
			{historyEntries, isFiltering} = @props

			# Limit number of entries by filter/historyCount
			sliceCount = if isFiltering then @state.filterCount else @state.historyCount
			slicedHistoryEntries = historyEntries.slice 0, sliceCount

			R.div({
				ref: 'entriesListView'
				id: 'entriesListView'
				className: showWhen not slicedHistoryEntries.isEmpty()
			},
				EntryDateNavigator({
					ref: 'entryDateNavigator'
					historyEntries: @props.historyEntries
					onSelect: @_scrollToEntryDate
				})

				(slicedHistoryEntries.map (entry) =>
					switch entry.get('entryType')
						when 'progNote'
							# Combine entry with @props + key
							ProgNoteContainer(_.extend entry.toObject(), @props, {
								key: entry.get('id')
							})

						when 'globalEvent'
							GlobalEventView({
								key: entry.get('id')
								globalEvent: entry.get('globalEvent')
								programsById: @props.programsById
							})

						else
							throw new Error "Unknown historyEntries entryType: \"#{entry.get('entryType')}\""
				)
			)


	ProgNoteContainer = React.createFactory React.createClass
		displayName: 'ProgNoteContainer'
		mixins: [React.addons.PureRenderMixin]

		render: ->
			{isEditing, filteredProgNote, progEvents, globalEvents, dataTypeFilter} = @props

			progNote = @props.progNoteHistory.last()
			progNoteId = progNote.get('id')

			firstProgNoteRev = @props.progNoteHistory.first()
			userProgramId = firstProgNoteRev.get('authorProgramId')
			userProgram = @props.programsById.get(userProgramId) or Imm.Map()


			# TODO: Refactor to extended props

			if progNote.get('status') is 'cancelled'
				return CancelledProgNoteView({
					progNoteHistory: @props.progNoteHistory
					filteredProgNote
					dataTypeFilter
					attachments: @props.attachments
					progEvents
					globalEvents
					eventTypes: @props.eventTypes
					clientFile: @props.clientFile
					userProgram
					planTargetsById: @props.planTargetsById
					setSelectedItem: @props.setSelectedItem
					selectProgNote: @props.selectProgNote
					isReadOnly: @props.isReadOnly

					isEditing: @props.isEditing
					transientData: @props.transientData
					startRevisingProgNote: @props.startRevisingProgNote
					cancelRevisingProgNote: @props.cancelRevisingProgNote
					updateBasicUnitNotes: @props.updateBasicUnitNotes
					updatePlanTargetNotes: @props.updatePlanTargetNotes
					updatePlanTargetMetric: @props.updatePlanTargetMetric
					updateProgEvent: @props.updateProgEvent
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
						dataTypeFilter
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
						filteredProgNote
						dataTypeFilter
						progNoteHistory: @props.progNoteHistory
						progEvents
						globalEvents
						userProgram
						planTargetsById: @props.planTargetsById
						eventTypes: @props.eventTypes
						clientFile: @props.clientFile
						setSelectedItem: @props.setSelectedItem
						selectProgNote: @props.selectProgNote
						setEditingProgNoteId: @props.setEditingProgNoteId
						updatePlanTargetNotes: @props.updatePlanTargetNotes
						isReadOnly: @props.isReadOnly

						isEditing
						transientData: @props.transientData
						startRevisingProgNote: @props.startRevisingProgNote
						cancelRevisingProgNote: @props.cancelRevisingProgNote
						updateBasicUnitNotes: @props.updateBasicUnitNotes
						updateBasicMetric: @props.updateBasicMetric
						updatePlanTargetMetric: @props.updatePlanTargetMetric
						updateProgEvent: @props.updateProgEvent
						saveProgNoteRevision: @props.saveProgNoteRevision
					})
				else
					throw new Error "unknown prognote type: #{progNote.get('type')}"


	QuickNoteView = React.createFactory React.createClass
		displayName: 'QuickNoteView'
		mixins: [React.addons.PureRenderMixin]
		# TODO: propTypes

		render: ->
			{isEditing, dataTypeFilter} = @props

			# Don't render anything if only events are shown
			if dataTypeFilter is 'events' and not isEditing
				return null

			progNote = if isEditing then @props.transientData.get('progNote') else @props.progNote

			if @props.attachments?
				attachmentText = " " + @props.attachments.get('filename')

			R.div({
				id: "entry-#{progNote.get('id')}"
				className: [
					'entry basic progNote'
					'isEditing' if isEditing
				].join ' '
			},
				EntryHeader({
					revisionHistory: @props.progNoteHistory
					userProgram: @props.userProgram

					isReadOnly: @props.isReadOnly
					progNote: @props.progNote
					filteredProgNote: @props.filteredProgNote
					progNoteHistory: @props.progNoteHistory
					progEvents: @props.progEvents
					globalEvents: @props.globalEvents
					clientFile: @props.clientFile
					isEditing

					startRevisingProgNote: @props.startRevisingProgNote
					selectProgNote: @props.selectProgNote
				})
				R.div({className: 'notes'},
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
					(@props.attachments.map (attachment) =>
						{id, filename} = attachment.toObject()
						fileExtension = Path.extname filename

						R.a({
							key: id
							className: 'attachment'
							onClick: @_openAttachment.bind null, attachment
						},
							FaIcon(fileExtension)
							' '
							filename
						)
					)
				)
			)

		_openAttachment: (attachment) ->
			attachmentId = attachment.get('id')
			clientFileId = @props.clientFile.get('id')

			global.ActiveSession.persist.attachments.readLatestRevisions clientFileId, attachmentId, 1, (err, results) ->
				if err
					if err instanceof Persist.IOError
						Bootbox.alert """
							An error occurred.  Please check your network connection and try again.
						"""
						return

					CrashHandler.handle err
					return

				attachment = results.first()

				encodedData = attachment.get('encodedData')
				filename = attachment.get('filename')

				if filename?
					# Absolute path required for windows
					filepath = Path.join process.cwd(), Config.backend.dataDirectory, '_tmp', filename
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
		# TODO: propTypes

		render: ->
			{isEditing, dataTypeFilter} = @props

			# Use transient data when isEditing
			progNote = if isEditing then @props.transientData.get('progNote') else @props.filteredProgNote
			progEvents = if isEditing then @props.transientData.get('progEvents') else @props.progEvents


			R.div({
				id: "entry-#{progNote.get('id')}"
				className: 'entry full progNote'
			},
				EntryHeader({
					revisionHistory: @props.progNoteHistory
					userProgram: @props.userProgram

					isReadOnly: @props.isReadOnly
					progNote: @props.progNote
					filteredProgNote: @props.filteredProgNote
					progNoteHistory: @props.progNoteHistory
					progEvents: @props.progEvents
					globalEvents: @props.globalEvents
					clientFile: @props.clientFile
					isEditing

					startRevisingProgNote: @props.startRevisingProgNote
					selectProgNote: @props.selectProgNote
				})
				R.div({className: 'progNoteList'},
					(progNote.get('units').map (unit) =>
						unitId = unit.get 'id'

						# TODO: Make these into components
						(switch unit.get('type')
							when 'basic'
								if unit.get('notes')
									R.div({
										className: [
											'basic unit'
											"unitId-#{unitId}"
											'isEditing' if isEditing
											showWhen dataTypeFilter isnt 'events' or isEditing
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
									className: [
										'plan unit'
										showWhen dataTypeFilter isnt 'events' or isEditing
									].join ' '
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
												planTargetsById = @props.planTargetsById.map (target) -> target.get('revisions').first()
												targetId = target.get('id')
												# Use the up-to-date name & description for header display
												mostRecentTargetRevision = planTargetsById.get targetId

												R.div({
													key: targetId
													className: [
														'target'
														"targetId-#{targetId}"
														'isEditing' if isEditing
													].join ' '
													onClick: @_selectPlanSectionTarget.bind(null, unit, section, mostRecentTargetRevision)
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
																tooltipViewport: '#entriesListView'
																onChange: @props.updatePlanTargetMetric.bind(
																	null,
																	unitId, sectionId, targetId, metricId
																)
																onFocus: @_selectPlanSectionTarget.bind(null, unit, section, mostRecentTargetRevision)
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
						R.div({
							className: [
								'basic unit'
								showWhen dataTypeFilter isnt 'events'
							].join ' '
						},
							R.h3({}, "Shift Summary")
							R.div({className: 'notes'},
								renderLineBreaks progNote.get('summary')
							)
						)
					)

					(unless progEvents.isEmpty()
						R.div({
							className: [
								'progEvents'
								showWhen not dataTypeFilter or (dataTypeFilter isnt 'targets') or isEditing
							].join ' '
						},
							# Don't need to show the Events header when we're only looking at events
							(if dataTypeFilter isnt 'events' or isEditing
								R.h3({}, Term 'Events')
							)

							(progEvents.map (progEvent, index) =>
								ProgEventWidget({
									key: progEvent.get('id')
									format: 'large'
									progEvent
									eventTypes: @props.eventTypes
									isEditing
									updateProgEvent: @props.updateProgEvent.bind null, index
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

		_selectPlanSectionTarget: (unit, section, mostRecentTargetRevision) ->
			@props.setSelectedItem Imm.fromJS {
				type: 'planSectionTarget'
				unitId: unit.get('id')
				sectionId: section.get('id')
				targetId: mostRecentTargetRevision.get('id')
				targetName: mostRecentTargetRevision.get('name')
				targetDescription: mostRecentTargetRevision.get('description')
				progNoteId: @props.progNote.get('id')
			}


	CancelledProgNoteView = React.createFactory React.createClass
		displayName: 'CancelledProgNoteView'
		mixins: [React.addons.PureRenderMixin]
		# TODO: propTypes

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

			return R.div({
				id: "entry-#{firstRev.get('id')}"
				className: 'entry cancelStub'
			},
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
					"Discarded: "
					formatTimestamp(firstRev.get('backdate') or firstRev.get('timestamp'))
					" (late entry)" if firstRev.get('backdate')
				),

				R.div({className: "details #{showWhen @state.isExpanded}"},
					R.h4({},
						"Discarded by "
						statusChangeRev.get('author')
						" on "
						formatTimestamp statusChangeRev.get('timestamp')
					),
					R.h4({}, "Reason for discarding:")
					R.div({className: 'reason'},
						renderLineBreaks latestRev.get('statusReason')
					)

					switch latestRev.get('type')
						when 'basic'
							QuickNoteView({
								planTargetsById: @props.planTargetsById
								progNote: @props.progNoteHistory.last()
								progNoteHistory: @props.progNoteHistory
								attachments: @props.attachments
								clientFile: @props.clientFile
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
								planTargetsById: @props.planTargetsById
								progNote: @props.progNoteHistory.last()
								filteredProgNote: @props.filteredProgNote
								dataTypeFilter: @props.dataTypeFilter
								progNoteHistory: @props.progNoteHistory
								progEvents: @props.progEvents
								globalEvents: @props.globalEvents
								eventTypes: @props.eventTypes
								userProgram: @props.userProgram
								clientFile: @props.clientFile
								setSelectedItem: @props.setSelectedItem
								selectProgNote: @props.selectProgNote
								isReadOnly: true

								isEditing: @props.isEditing
								transientData: @props.transientData
								startRevisingProgNote: @props.startRevisingProgNote
								cancelRevisingProgNote: @props.cancelRevisingProgNote
								updatePlanTargetNotes: @props.updatePlanTargetNotes
								updatePlanTargetMetric: @props.updatePlanTargetMetric
								updateProgEvent: @props.updateProgEvent
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
		# TODO: propTypes

		getDefaultProps: -> {
			progEvents: Imm.List()
			globalEvents: Imm.List()
		}

		getDefaultProps: -> {
			progEvents: Imm.List()
			globalEvents: Imm.List()
		}

		render: ->
			{
				userProgram
				revisionHistory

				isEditing
				isReadOnly
				progNote
				filteredProgNote
				progNoteHistory
				progEvents
				globalEvents
				clientFile
				startRevisingProgNote
				selectProgNote
			} = @props

			userIsAuthor = progNote? and (progNote.get('author') is global.ActiveSession.userName)
			canViewOptions = progNote? and not isEditing
			canModify = userIsAuthor and not isReadOnly

			hasRevisions = revisionHistory.size > 1
			numberOfRevisions = revisionHistory.size - 1
			hasMultipleRevisions = numberOfRevisions > 1

			firstRevision = revisionHistory.first() # Use original revision's data
			timestamp = (
				firstRevision.get('startTimestamp') or
				firstRevision.get('backdate') or
				firstRevision.get('timestamp')
			)


			R.div({className: 'entryHeader'},
				R.div({className: 'timestamp'},
					formatTimestamp(timestamp, @props.dateFormat)

					(if firstRevision.get('backdate')
						R.span({className: 'lateTimestamp'},
							"(late entry)"
						)
					)
				)

				(if progNote? and hasRevisions
					R.div({className: 'revisions'},
						R.a({
							className: 'selectProgNoteButton'
							onClick: selectProgNote.bind null, progNote
						},
							"#{numberOfRevisions} revision#{if hasMultipleRevisions then 's' else ''}"
						)
					)
				)

				R.div({className: 'author'},
					'by '
					firstRevision.get('authorDisplayName') or firstRevision.get('author')

					(if userProgram and not userProgram.isEmpty()
						ColorKeyBubble({
							colorKeyHex: userProgram.get('colorKeyHex')
							popover: {
								title: userProgram.get('name')
								content: userProgram.get('description')
								placement: 'left'
							}
						})
					)
				)

				(if canViewOptions
					R.div({className: 'options'},
						B.DropdownButton({
							id: "entryHeaderDropdown-#{progNote.get('id')}"
							className: 'entryHeaderDropdown'
							pullRight: true
							noCaret: true
							title: FaIcon('ellipsis-v', {className:'menuItemIcon'})
						},
							(if canModify
								B.MenuItem({onClick: startRevisingProgNote.bind null, progNote, progEvents},
									"Edit"
								)
							)

							B.MenuItem({onClick: @_print.bind null, filteredProgNote, progEvents, clientFile},
								"Print"
							)

							(if canModify
								B.MenuItem({onClick: @_openCancelProgNoteDialog},
									OpenDialogLink({
										ref: 'cancelButton'
										className: 'cancelNote'
										dialog: CancelProgNoteDialog
										progNote
										progEvents
										globalEvents
									}, "Discard")
								)
							)
						)
					)
				)

			)

		_openCancelProgNoteDialog: (event) ->
			@refs.cancelButton.open(event)

		_print: (progNote, progEvents, clientFile) ->
			openWindow {
				page: 'printPreview'
				dataSet: JSON.stringify([
					{
						format: 'progNote'
						data: progNote
						progEvents
						clientFile
					}
				])
			}


	GlobalEventView = React.createFactory React.createClass
		displayName: 'GlobalEventView'
		mixins: [React.addons.PureRenderMixin]
		# TODO: propTypes

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

			return R.div({
				id: "entry-#{globalEvent.get('id')}"
				className: 'entry globalEventView'
			},
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


	# Applies selected styles without having to re-render entire EntriesListView tree
	InlineSelectedItemStyles = ({selectedItem}) ->
		R.style({},
			(switch selectedItem.get('type')
				when 'planSectionTarget' # Target entry history
					"""
						div.target.targetId-#{selectedItem.get('targetId')}:not(.isEditing) {
							padding-left: 20px !important;
							padding-right: 0px !important;
							border-left: 2px solid #3176aa !important;
							color: #3176aa !important;
						}

						div.target.targetId-#{selectedItem.get('targetId')}:not(.isEditing) h3 {
							opacity: 1 !important;
						}

						div.target.targetId-#{selectedItem.get('targetId')}:not(.isEditing) .notes {
							opacity: 1 !important;
						}
					"""

				when 'quickNote' # QuickNote entry history
					"""
						div.basic.progNote:not(.isEditing) .notes > div {
							padding-left: 20px !important;
							padding-right: 0px !important;
							border-left: 2px solid #3176aa !important;
							color: #3176aa !important;

							opacity: 1 !important;
						}
					"""

				when 'basicUnit' # General 'Notes' entry history (TODO: what > 1 basic unit?)
					"""
						div.basic.unit.unitId-#{selectedItem.get('unitId')}:not(.isEditing) {
							padding-left: 20px !important;
							padding-right: 0px !important;
							border-left: 2px solid #3176aa !important;
							color: #3176aa !important;

							opacity: 1 !important;
						}
					"""

				when 'progNote' # ProgNote revisions
					"""
						div.progNote#entry-#{selectedItem.get('progNoteId')}:not(.isEditing) .revisions {
							border-left: 2px solid #3176aa !important;
						}

						div.progNote#entry-#{selectedItem.get('progNoteId')}:not(.isEditing) .revisions a {
							color: #3176aa !important;
							opacity: 1 !important;
						}
					"""

				else
					throw new Error "Unknown selectedItem type #{selectedItem.get('type')} for InlineSelectedItemStyles"
			)
		)


	filterEmptyProgNoteValues = (progNote) ->
		# Don't bother filtering a quickNote (doesn't have units)
		unless progNote.has 'units'
			return progNote

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
						targetMetrics = target.get('metrics').filterNot (metric) -> not metric.get('value')

						return target
						.set('metrics', targetMetrics)
						.remove('description') # We don't need target description snapshot displayed/searched

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


	return ProgNotesTab

module.exports = {load}
