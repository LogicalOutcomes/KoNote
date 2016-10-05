# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Read/Write event information view contained within eventTab

Imm = require 'immutable'
Moment = require 'moment'
_ = require 'underscore'
nlp = require 'nlp_compromise'
Term = require '../term'
ImmPropTypes = require 'react-immutable-proptypes'
{TimestampFormat} = require '../persist/utils'


load = (win) ->
	$ = win.jQuery
	React = win.React
	{PropTypes} = React
	R = React.DOM
	Bootbox = win.bootbox

	B = require('../utils/reactBootstrap').load(win, 'DropdownButton', 'MenuItem')

	Dialog = require('../dialog').load(win)
	WithTooltip = require('../withTooltip').load(win)
	OpenDialogLink = require('../openDialogLink').load(win)
	ProgramsDropdown = require('../programsDropdown').load(win)
	ExpandingTextArea = require('../expandingTextArea').load(win)

	{FaIcon, renderName, showWhen, formatTimestamp} = require('../utils').load(win)


	EventTabView = React.createFactory React.createClass
		displayName: 'EventTabView'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			# Use backdate instead of current date (if exists)
			if @props.backdate
				startDate = Moment(@props.backdate, TimestampFormat)
			else
				startDate = Moment()

			return {
				title: ''
				description: ''
				typeId: ''
				isGlobalEvent: null

				startDate
				startTime: ''
				endDate: ''
				endTime: ''

				isDateSpan: false
				usesTimeOfDay: false
			}

		componentDidMount: ->
			# Initialize datepickers, bind to @state

			# Grab jQ contexts
			$startDate = $(@refs.startDate)
			$startTime = $(@refs.startTime)
			$endDate = $(@refs.endDate)
			$endTime = $(@refs.endTime)

			$startDate.datetimepicker({
				useCurrent: false
				format: 'Do MMM, \'YY'
				defaultDate: @state.startDate.toDate()
				widgetPositioning: {
					horizontal: 'right'
				}
			}).on 'dp.change', (thisInput) =>
				$endDate.data('DateTimePicker').minDate(thisInput.date)
				@setState {startDate: thisInput.date}

			$startTime.datetimepicker({
				useCurrent: false
				format: 'hh:mm a'
				widgetPositioning: {
					horizontal: 'right'
				}
			}).on 'dp.change', (thisInput) =>
				@setState {startTime: thisInput.date}


			$endDate.datetimepicker({
				minDate: @state.startDate.toDate()
				useCurrent: false
				format: 'Do MMM, \'YY'
				widgetPositioning: {
					horizontal: 'right'
				}
			}).on 'dp.change', (thisInput) =>
				$startDate.data('DateTimePicker').maxDate(thisInput.date)
				@setState {endDate: thisInput.date}

			$endTime.datetimepicker({
				useCurrent: false
				format: 'hh:mm a'
				widgetPositioning: {
					horizontal: 'right'
				}
			}).on 'dp.change', (thisInput) =>
				@setState {endTime: thisInput.date}

		render: ->
			selectedEventType = @props.eventTypes.find (type) => type.get('id') is @state.typeId

			return R.div({
				className: [
					'eventView'
					showWhen @props.isBeingEdited or not @props.editMode
				].join ' '
			},
				R.form({className: showWhen @props.isBeingEdited},
					R.button({
						className: 'btn btn-danger closeButton'
						onClick: @_closeForm
					},
						FaIcon('times')
					)
					R.div({className: 'form-group'},
						R.label({}, "Name")
						R.input({
							id: 'nameInput'
							className: 'form-control'
							value: @state.title
							onChange: @_updateTitle
							placeholder: "Name of #{Term 'event'}"
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "Description")
						ExpandingTextArea({
							value: @state.description
							onChange: @_updateDescription
							placeholder: "Describe details (optional)"
						})
					)

					(unless @props.eventTypes.isEmpty()
						R.div({className: 'form-group eventTypeContainer'},
							R.label({}, "Select #{Term 'Event Type'}")

							B.DropdownButton({
								title: if selectedEventType? then selectedEventType.get('name') else "No Type"
							},
								if selectedEventType?
									[
										B.MenuItem({
											onClick: @_updateTypeId.bind null, ''
										},
											"None "
											FaIcon('ban')
										)
										B.MenuItem({divider: true})
									]


								(@props.eventTypes
								.filter (eventType) =>
									eventType.get('status') is 'default'
								.map (eventType) =>
									B.MenuItem({
										key: eventType.get('id')
										onClick: @_updateTypeId.bind null, eventType.get('id')
									},
										R.div({
											onClick: @_updateTypeId.bind null, eventType.get('id')
											style:
												borderRight: "5px solid #{eventType.get('colorKeyHex')}"
										},
											eventType.get('name')
										)
									)
								)
							)
						)
					)

					R.div({className: 'globalEventContainer'},
						WithTooltip({
							title: "#{Term 'Client'} must be assigned to 1 or more #{Term 'programs'}"
							showTooltip: @props.clientPrograms.isEmpty()
							placement: 'left'
						},
							R.div({
								className: [
									'checkbox'
									'disabled' if @props.clientPrograms.isEmpty()
								].join ' '
							},
								R.label({},
									R.input({
										disabled: @props.clientPrograms.isEmpty()
										type: 'checkbox'
										onClick: @_toggleIsGlobalEvent
										checked: @state.isGlobalEvent
									})
									"Make this a #{Term 'global event'}"

									(unless @props.clientPrograms.isEmpty()
										WithTooltip({
											title: "A copy of this #{Term 'event'} will visible to all #{Term 'client files'}"
										},
											FaIcon('question-circle')
										)
									)
								)
							)
						)
					)

					R.div({className: "dateGroup"},
						R.div({className: 'form-group date'},
							R.label({}, if @state.isDateSpan then "Start Date" else "Date")
							R.input({
								ref: 'startDate'
								className: 'form-control'
								type: 'text'
							})
						)
						R.div({className: "form-group timeOfDay #{showWhen @state.usesTimeOfDay}"},
							R.label({},
								R.span({onClick: @_toggleUsesTimeOfDay},
									FaIcon('clock-o')
									FaIcon('times')
								)
							)
							R.input({
								ref: 'startTime'
								className: 'form-control'
								type: 'text'
								placeholder: "00:00 --"
							})
						)
						R.div({className: "form-group useTimeOfDay #{showWhen not @state.usesTimeOfDay}"}
							R.button({
								className: 'btn btn-default'
								onClick: @_toggleUsesTimeOfDay
							}, FaIcon('clock-o'))
						)
					)
					R.div({className: "dateGroup #{showWhen @state.isDateSpan}"},
						R.div({
							className: 'form-group removeDateSpan'
						}
							R.span({onClick: @_toggleIsDateSpan},
								FaIcon('arrow-right')
								FaIcon('times')
							)
						)
						R.div({className: 'form-group date'},
							R.label({}, "End Date")
							R.input({
								ref: 'endDate'
								className: 'form-control'
								type: 'text'
								placeholder: "Select date"
							})
						)
						R.div({className: "form-group timeOfDay #{showWhen @state.usesTimeOfDay}"},
							R.label({},
								R.span({onClick: @_toggleUsesTimeOfDay},
									FaIcon('clock-o')
									FaIcon('times')
								)
							)
							R.input({
								ref: 'endTime'
								className: 'form-control'
								type: 'text'
								placeholder: "00:00 --"
							})
						)
						R.div({className: "form-group useTimeOfDay #{showWhen not @state.usesTimeOfDay}"}
							R.button({
								className: 'btn btn-default'
								onClick: @_toggleUsesTimeOfDay
							}, FaIcon('clock-o'))
						)
					)
					R.div({
						className: 'btn-toolbar'
					},
						R.button({
							className: "btn btn-default #{showWhen not @state.isDateSpan}"
							onClick: @_toggleIsDateSpan
						},
							"Add End Date"
						)

						# TODO: Refactor to something more generic
						(if @state.isGlobalEvent
							OpenDialogLink({
								dialog: AmendGlobalEventDialog
								eventData: @_compiledFormData()
								clientFileId: @props.clientFileId
								clientPrograms: @props.clientPrograms
								onSuccess: @_saveProgEvent
							},
								R.button({
									className: "btn btn-success #{'fullWidth' if @state.isDateSpan}"
									type: 'submit'
									disabled: @_formIsInvalid()
								},
									"Save "
									FaIcon('check')
								)
							)
						else
							R.button({
								className: "btn btn-success #{'fullWidth' if @state.isDateSpan}"
								type: 'submit'
								onClick: @_submit
								disabled: @_formIsInvalid()
							},
								"Save "
								FaIcon('check')
							)
						)
					)
				)

				R.div({className: "details #{showWhen not @props.isBeingEdited}"},
					R.div({className: 'title'}, @props.data.get('title'))
					R.div({className: 'description'}, @props.data.get('description'))
					R.div({className: 'timeSpan'},
						R.div({className: 'start'},
							"From: " if @props.data.get('endTimestamp')
							@_showTimestamp @props.data.get('startTimestamp')
						)
						(if @props.data.get('endTimestamp')
							R.div({className: 'end'},
								"Until: "
								@_showTimestamp @props.data.get('endTimestamp')
							)
						)
					)
				)
		)

		_toggleUsesTimeOfDay: (event) ->
			event.preventDefault()
			@setState {usesTimeOfDay: not @state.usesTimeOfDay}, =>

		_showTimestamp: (timestamp) ->
			moment = Moment(timestamp, TimestampFormat)

			if moment.isValid
				return formatTimestamp(timestamp)
			else
				return "Invalid Moment"

		_toggleIsDateSpan: (event) ->
			event.preventDefault()
			@setState {isDateSpan: not @state.isDateSpan}, =>
				# Focus endDate if enabling
				if @state.isDateSpan
					@refs.endDate.focus()

		_updateTitle: (event) ->
			@setState {title: event.target.value}

		_updateDescription: (event) ->
			@setState {description: event.target.value}

		_updateTypeId: (typeId) ->
			@setState {typeId}

		_formIsInvalid: ->
			return not @state.title or not @state.startDate or
			(@state.isDateSpan and not @state.endDate) or
			(@state.usesTimeOfDay and not @state.startTime) or
			(@state.usesTimeOfDay and @state.isDateSpan and not @state.endTime)

		_toggleIsGlobalEvent: ->
			@setState {isGlobalEvent: not @state.isGlobalEvent}

		_closeForm: (event) ->
			event.preventDefault()

			if (
				@state.title or @state.endDate or @state.description or
				@props.selectedEventPlanRelation or @state.typeId
			)
				Bootbox.confirm "Cancel #{Term 'event'} editing?", (ok) =>
					if ok
						# Make sure all states are reset, then cancel
						@setState @props.data, =>
							@props.cancel @props.atIndex
			else
				@setState @props.data, =>
					@props.cancel @props.atIndex

		_submit: (event) ->
			event.preventDefault()
			progEvent = @_compiledFormData()
			@_saveProgEvent progEvent

		_saveProgEvent: (progEvent) ->
			@props.saveProgEvent progEvent, @props.atIndex

		_compiledFormData: ->
			isOneFullDay = null

			# Start with dates
			startTimestamp = @state.startDate
			endTimestamp = @state.endDate

			# Extract time from start/endTime
			if @state.usesTimeOfDay
				startTimestamp = startTimestamp.set('hour', @state.startTime.hour()).set('minute', @state.startTime.minute())

				if @state.isDateSpan
					endTimestamp = if endTimestamp
						endTimestamp.set('hour', @state.endTime.hour()).set('minute', @state.endTime.minute())
					else
						''
			# Default to start/end of day for dates
			else
				startTimestamp = startTimestamp.startOf('day')

				if @state.isDateSpan
					endTimestamp = if endTimestamp then endTimestamp.endOf('day') else Moment()
				else
					# If only a single date was provided, assume it's an all-day event
					isOneFullDay = true
					endTimestamp = Moment(startTimestamp).endOf('day')

			progEventObject = Imm.fromJS {
				title: @state.title
				description: @state.description
				typeId: @state.typeId
				startTimestamp: startTimestamp.format(TimestampFormat)
				endTimestamp: if @state.isDateSpan or isOneFullDay then endTimestamp.format(TimestampFormat) else ''
			}

			return progEventObject


	AmendGlobalEventDialog = React.createFactory React.createClass
		displayName: 'AmendGlobalEventDialog'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			# Use client's program if has only 1
			# Otherwise use the program that matched userProgramId
			# Else, user must select program from list
			clientHasPrograms = not @props.clientPrograms.isEmpty()
			userProgramId = global.ActiveSession.programId

			program = Imm.Map()
			@programSelectionRequired = false

			if clientHasPrograms

				if @props.clientPrograms.size is 1
					console.log "Only has one, chose that!"
					programId = @props.clientPrograms.first()

				else
					console.log "Testing programs"
					matchingProgram = @props.clientPrograms.find (program) -> program.get('id') is userProgramId

					if matchingProgram?
						console.log "Matching!", matchingProgram.toJS()
						programId = matchingProgram
					else
						console.log "Selection required"
						@programSelectionRequired = true


			return {
				title: @props.eventData.get('title')
				description: @props.eventData.get('description')
				program
			}

		propTypes: {
			eventData: ImmPropTypes.map.isRequired
			clientFileId: PropTypes.string.isRequired
			clientPrograms: ImmPropTypes.list.isRequired
		}

		render: ->
			flaggedNames = @_generateFlaggedNames()

			return Dialog({
				ref: 'dialog'
				title: "Amend #{Term 'Global Event'}"
				onClose: @props.onClose
			},
				R.div({className: 'amendGlobalEventDialog'},
					R.p({},
						"Please remove any sensitive and/or #{Term 'client'}-specific information
						to be saved in the #{Term 'global event'}, which will be visible
						in all #{Term 'client files'}."
					)

					(if flaggedNames.length > 0
						R.div({className: 'flaggedNames'},
							FaIcon('flag')
							"Flagged: "
							flaggedNames.join ', '
						)
					)

					R.div({className: 'form-group'},
						R.label({}, "Name")
						R.input({
							className: 'form-control'
							value: @state.title
							onChange: @_updateTitle
						})
					)

					R.div({className: 'form-group'},
						R.label({}, "Description")
						ExpandingTextArea({
							value: @state.description
							onChange: @_updateDescription
						})
					)

					(if @programSelectionRequired
						R.div({className: 'form-group'},
							R.hr({})

							R.label({}, "Select a program for this #{Term 'global event'}")
							ProgramsDropdown({
								selectedProgram: @state.program
								programs: @props.clientPrograms
								onSelect: @_updateProgram
								excludeNone: true
							})

							R.hr({})
						)
					)

					R.div({className: 'btn-toolbar pull-right'},
						R.button({
							className: 'btn btn-default'
							onClick: @props.onCancel
						},
							"Cancel"
						)
						R.button({
							className: 'btn btn-success'
							onClick: @_submit
							disabled: @_formIsInvalid()
						},
							"Save #{Term 'Global Event'} "
							FaIcon('check')
						)
					)
				)
			)

		_updateTitle: (event) ->
			title = event.target.value
			@setState {title}

		_updateDescription: (event) ->
			description = event.target.value
			@setState {description}

		_updateProgram: (program) ->
			@setState {program}

		_formIsInvalid: ->
			return not @state.title or
			not @state.description or
			(@programSelectionRequired and not @state.program.has('name'))

		_generateFlaggedNames: ->
			# TODO: Process the title as well?
			people = nlp.text(@props.eventData.get('description')).people()
			names = []

			for i of people
				names.push(people[i].normal) unless people[i].pos.Pronoun

			return names

		_submit: (event) ->
			event.preventDefault()

			# Attach globalEvent as a property of the progEvent
			# which will get extracted during final save process
			globalEvent = Imm.fromJS(@props.eventData)
			.set('title', @state.title)
			.set('description', @state.description)
			.set('clientFileId', @props.clientFileId)
			.set('programId', @state.program.get('id') or '')

			progEvent = @props.eventData.set('globalEvent', globalEvent)

			@props.onSuccess(progEvent)


	return EventTabView

module.exports = {load}