# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Read/Write event information view contained within eventTab

Imm = require 'immutable'
Moment = require 'moment'
nlp = require 'nlp_compromise'
Term = require '../term'
{TimestampFormat} = require '../persist/utils'


load = (win) ->
	$ = win.jQuery
	React = win.React
	R = React.DOM
	Bootbox = win.bootbox

	Dialog = require('../dialog').load(win)
	WithTooltip = require('../withTooltip').load(win)
	OpenDialogLink = require('../openDialogLink').load(win)
	ColorKeyBubble = require('../colorKeyBubble').load(win)
	ProgramsDropdown = require('../programsDropdown').load(win)
	TimeSpanSelection = require('../timeSpanSelection').load(win)
	ExpandingTextArea = require('../expandingTextArea').load(win)
	EventTypesDropdown = require('../eventTypesDropdown').load(win)

	{FaIcon, renderName, showWhen, formatTimestamp, renderTimeSpan, makeMoment} = require('../utils').load(win)


	EventTabView = React.createFactory React.createClass
		displayName: 'EventTabView'
		mixins: [React.addons.PureRenderMixin]

		componentDidMount: ->
			@refs.description.focus()

		componentDidUpdate: (oldProps, oldState) ->
			if (@props.isBeingEdited isnt oldProps.isBeingEdited) and @props.isBeingEdited
				@refs.description.focus()

		getInitialState: ->
			# Use progNote's back/date to start (full-day event)
			startingDate = if @props.backdate then makeMoment(@props.backdate) else Moment()
			startTimestamp = startingDate.startOf('day').format(TimestampFormat)
			endTimestamp = startingDate.endOf('day').format(TimestampFormat)

			state = {
				progEvent: Imm.Map {
					title: ''
					description: ''
					typeId: ''
					startTimestamp
					endTimestamp
				}
				isGlobalEvent: null
			}

			@initialState = state # Cache for later comparisons
			return state

		render: ->
			progEvent = @state.progEvent
			typeId = progEvent.get 'typeId'
			selectedEventType = @props.eventTypes.find (type) => type.get('id') is typeId

			formIsValid = @_formIsValid()
			hasChanges = @_hasChanges()

			return R.div({
				className: [
					'eventView'
					showWhen @props.isBeingEdited or not @props.editMode
				].join ' '
			},
				R.form({className: showWhen @props.isBeingEdited},
					R.button({
						className: 'btn btn-danger closeButton'
						onClick: @_closeForm.bind null, hasChanges
					},
						FaIcon('times')
					)
					(if not @props.eventTypes.isEmpty()
						R.div({className: 'form-group titleContainer'},
							R.div({},
								R.label({}, Term 'Event Type')
								R.div({},
									EventTypesDropdown({
										selectedEventType
										eventTypes: @props.eventTypes
										onSelect: @_updateTypeId
										typeId
									})
								)
							)
						)
					)
					R.div({className: 'form-group'},
						R.label({}, "Description")
						ExpandingTextArea({
							ref: 'description'
							value: progEvent.get('description')
							onChange: @_updateDescription
							placeholder: "Describe details (optional)"
						})
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
											title: "A copy of this #{Term 'event'}
											will visible to all #{Term 'client files'}"
										},
											FaIcon('question-circle')
										)
									)
								)
							)
						)
					)

					TimeSpanSelection({
						startTimestamp: progEvent.get('startTimestamp')
						endTimestamp: progEvent.get('endTimestamp')
						updateTimestamps: @_updateTimestamps
						widgetPositioning: {
							horizontal: 'right'
							vertical: 'top'
						}
					})

					R.div({className: 'btn-toolbar'},

						# TODO: Refactor to something more generic
						(if @state.isGlobalEvent
							OpenDialogLink({
								dialog: AmendGlobalEventDialog
								progEvent
								clientFileId: @props.clientFileId
								clientPrograms: @props.clientPrograms
								onSuccess: @_saveProgEvent
							},
								R.button({
									className: 'btn btn-success btn-block'
									type: 'submit'
									disabled: not formIsValid or not hasChanges
								},
									"Save "
									FaIcon('check')
								)
							)
						else
							R.button({
								className: 'btn btn-success btn-block'
								type: 'submit'
								onClick: @_submit
								disabled: not formIsValid or not hasChanges
							},
								"Save "
								FaIcon('check')
							)
						)
					)
				)

				R.div({className: "details #{showWhen not @props.isBeingEdited}"},
					R.div({className: 'title'}, @props.progEvent.get('title'))
					R.div({className: 'description'}, @props.progEvent.get('description'))
					R.div({className: 'timeSpan'},
						renderTimeSpan(
							@props.progEvent.get('startTimestamp'), @props.progEvent.get('endTimestamp')
						)
					)
				)
		)

		_updateTitle: (event) ->
			progEvent = @state.progEvent.set 'title', event.target.value
			@setState {progEvent}

		_updateDescription: (event) ->
			progEvent = @state.progEvent.set 'description', event.target.value
			@setState {progEvent}

		_updateTypeId: (typeId) ->
			progEvent = @state.progEvent
			.set 'typeId', typeId
			.set 'title', '' # EventType takes place of 'title'

			@setState {progEvent}

		_updateTimestamps: ({startTimestamp, endTimestamp}) ->
			progEvent = @state.progEvent

			if startTimestamp?
				progEvent = progEvent.set 'startTimestamp', startTimestamp
			if endTimestamp?
				progEvent = progEvent.set 'endTimestamp', endTimestamp

			@setState {progEvent}

		_formIsValid: ->
			description = @state.progEvent.get('description')
			hasDescription = if description then description.trim() else description
			hasEventTypeId = @state.progEvent.get('typeId')

			# Needs to have a description or eventType
			return !!(hasDescription or hasEventTypeId)

		_hasChanges: ->
			if not @initialState then return false # Make sure initialState is mounted
			return !!@state.isGlobalEvent or not Imm.is @state.progEvent, @initialState.progEvent

		_toggleIsGlobalEvent: ->
			@setState {isGlobalEvent: not @state.isGlobalEvent}

		_closeForm: (hasChanges, event) ->
			event.preventDefault()

			if hasChanges
				Bootbox.confirm "Cancel #{Term 'event'} editing?", (ok) =>
					if ok
						@_resetProgEvent()
			else
				@_resetProgEvent()

		_resetProgEvent: ->
			@setState {progEvent: @props.progEvent}, =>
				@props.cancel()

		_submit: (event) ->
			event.preventDefault()
			@_saveProgEvent @state.progEvent

		_saveProgEvent: (progEvent) ->
			# Axe the title if an eventType is being used instead (#871)
			# Otherwise, make sure typeId isn't null
			if !!progEvent.get('typeId')
				progEvent = progEvent.set 'title', ''
			else
				progEvent = progEvent.set 'typeId', ''

			@props.saveProgEvent progEvent


	AmendGlobalEventDialog = React.createFactory React.createClass
		displayName: 'AmendGlobalEventDialog'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			# Use client's program if has only 1
			# Otherwise use the program that matches userProgramId
			# Else, user must select program from list
			userProgramId = global.ActiveSession.programId

			programId = ''
			@programSelectionRequired = false
			clientHasPrograms = not @props.clientPrograms.isEmpty()

			if clientHasPrograms

				if @props.clientPrograms.size is 1
					programId = @props.clientPrograms.first().get('id')

				else
					clientIsInUserProgram = @props.clientPrograms.some (p) -> p.get('id') is userProgramId

					if clientIsInUserProgram
						programId = userProgramId
					else
						@programSelectionRequired = true


			return {
				title: @props.progEvent.get('title')
				description: @props.progEvent.get('description')
				typeId: @props.progEvent.get('typeId') or ''
				programId
			}

		propTypes: {
			progEvent: React.PropTypes.instanceOf(Imm.Map).isRequired
			clientFileId: React.PropTypes.string.isRequired
			clientPrograms: React.PropTypes.instanceOf(Imm.List).isRequired
		}

		render: ->
			flaggedNames = @_generateFlaggedNames()
			selectedProgram = @props.clientPrograms.find (p) => p.get('id') is @state.programId


			return Dialog({
				ref: 'dialog'
				title: "Amend #{Term 'Global Event'}"
				onClose: @props.onClose
			},
				R.div({className: 'amendGlobalEventDialog'},
					R.p({},
						"Please remove any sensitive and/or #{Term 'client'}-specific information
						to be saved in the #{Term 'global event'}."
					)
					R.p({},
						"This information will appear for all #{Term 'client files'}"

						(if not @programSelectionRequired and selectedProgram?
							R.span({},
								" in: "
								ColorKeyBubble({
									colorKeyHex: selectedProgram.get('colorKeyHex')
								})
								' '
								R.strong({}, selectedProgram.get('name'))
							)
						else
							"in the program you specify."
						)
					)

					(if flaggedNames.length > 0
						R.div({className: 'flaggedNames'},
							FaIcon('flag')
							"Flagged: "
							flaggedNames.join ', '
						)
					)

					R.div({className: 'form-group'},
						R.label({}, "Description")
						ExpandingTextArea({
							value: @state.description
							onChange: @_updateDescription
							placeholder: if @state.typeId then "(optional)" else ''
						})
					)

					(if @programSelectionRequired and @props.clientPrograms.size > 1
						R.div({className: 'form-group'},
							R.hr({})

							R.label({}, "Select a program for this #{Term 'global event'}")
							ProgramsDropdown({
								selectedProgramId: @state.programId
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

		_updateDescription: (event) ->
			description = event.target.value
			@setState {description}

		_updateProgram: (programId) ->
			@setState {programId}

		_formIsInvalid: ->
			return not (@state.description or @state.typeId) or (@programSelectionRequired and not @state.programId)

		_generateFlaggedNames: ->
			# TODO: Process the title as well?
			people = nlp.text(@props.progEvent.get('description')).people()
			names = []

			for i of people
				names.push(people[i].normal) unless people[i].pos.Pronoun

			return names

		_submit: (event) ->
			event.preventDefault()

			# Set up globalEvent object
			globalEvent = @props.progEvent
			.set 'title', @state.title
			.set 'description', @state.description
			.set 'clientFileId', @props.clientFileId
			.set 'programId', @state.programId

			# Attach globalEvent as a property of the progEvent,
			# which will get extracted during final save process
			progEvent = @props.progEvent.set 'globalEvent', globalEvent

			@props.onSuccess(progEvent)


	return EventTabView

module.exports = {load}
