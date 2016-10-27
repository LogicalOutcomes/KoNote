# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Read/Write event information view contained within eventTab

Imm = require 'immutable'
Moment = require 'moment'
_ = require 'underscore'
nlp = require 'nlp_compromise'
Term = require '../term'
{TimestampFormat} = require '../persist/utils'


load = (win) ->
	$ = win.jQuery
	React = win.React
	R = React.DOM
	Bootbox = win.bootbox

	B = require('../utils/reactBootstrap').load(win, 'DropdownButton', 'MenuItem')

	Dialog = require('../dialog').load(win)
	WithTooltip = require('../withTooltip').load(win)
	OpenDialogLink = require('../openDialogLink').load(win)
	ProgramsDropdown = require('../programsDropdown').load(win)
	EventTypesDropdown = require('../eventTypesDropdown').load(win)
	TimeSpanSelection = require('../timeSpanSelection').load(win)
	ExpandingTextArea = require('../expandingTextArea').load(win)

	{FaIcon, renderName, showWhen, formatTimestamp, renderTimeSpan} = require('../utils').load(win)


	EventTabView = React.createFactory React.createClass
		displayName: 'EventTabView'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			# Use progNote's back/date to start (full-day event)
			startingDate = if @props.backdate then makeMoment(@props.backdate) else Moment()
			startTimestamp = startingDate.startOf('day').format(TimestampFormat)
			endTimestamp = startingDate.endOf('day').format(TimestampFormat)

			return {
				progEvent: Imm.Map {
					title: ''
					description: ''
					typeId: ''
					startTimestamp
					endTimestamp
				}
				isGlobalEvent: null
			}

		render: ->
			progEvent = @state.progEvent
			typeId = progEvent.get 'typeId'
			selectedEventType = @props.eventTypes.find (type) => type.get('id') is typeId

			formIsInvalid = @_formIsInvalid()
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
						onClick: @_closeForm
					},
						FaIcon('times')
					)
					R.div({className: 'form-group'},
						R.label({}, "Name")
						R.input({
							id: 'nameInput'
							className: 'form-control'
							value: progEvent.get('title')
							onChange: @_updateTitle
							placeholder: "Name of #{Term 'event'}"
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "Description")
						ExpandingTextArea({
							value: progEvent.get('description')
							onChange: @_updateDescription
							placeholder: "Describe details (optional)"
						})
					)

					(unless @props.eventTypes.isEmpty()
						EventTypesDropdown({
							selectedEventType
							eventTypes: @props.eventTypes
							onSelect: @_updateTypeId
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
											title: "A copy of this #{Term 'event'} will visible to all #{Term 'client files'}"
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
					})

					R.div({className: 'btn-toolbar'},

						# TODO: Refactor to something more generic
						(if @state.isGlobalEvent
							OpenDialogLink({
								dialog: AmendGlobalEventDialog
								eventData: progEvent
								clientFileId: @props.clientFileId
								clientPrograms: @props.clientPrograms
								onSuccess: @_saveProgEvent
							},
								R.button({
									className: 'btn btn-success'
									type: 'submit'
									disabled: formIsInvalid or not hasChanges
								},
									"Save "
									FaIcon('check')
								)
							)
						else
							R.button({
								className: 'btn btn-success'
								type: 'submit'
								onClick: @_submit
								disabled: formIsInvalid or not hasChanges
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
						renderTimeSpan @props.data.get('startTimestamp'), @props.data.get('endTimestamp')
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
			progEvent = @state.progEvent.set 'typeId', typeId
			@setState {progEvent}

		_updateTimestamps: ({startTimestamp, endTimestamp}) ->
			progEvent = @state.progEvent

			if startTimestamp?
				progEvent = progEvent.set 'startTimestamp', startTimestamp
			if endTimestamp?
				progEvent = progEvent.set 'endTimestamp', endTimestamp

			@setState {progEvent}

		_formIsInvalid: ->
			{title, description, startTimestamp} = @state.progEvent.toObject()
			return not title or not description or not startTimestamp

		_hasChanges: ->
			return not Imm.is @state.progEvent, @props.data

		_toggleIsGlobalEvent: ->
			@setState {isGlobalEvent: not @state.isGlobalEvent}

		_closeForm: (event) ->
			event.preventDefault()

			if @_hasChanges()
				Bootbox.confirm "Cancel #{Term 'event'} editing?", (ok) =>
					if ok
						@_resetProgEvent()
			else
				@_resetProgEvent()

		_resetProgEvent: ->
			@setState {progEvent: @props.data}, =>
				@props.cancel @props.atIndex

		_submit: (event) ->
			event.preventDefault()
			@_saveProgEvent @state.progEvent

		_saveProgEvent: (progEvent) ->
			@props.saveProgEvent progEvent, @props.atIndex


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
					programId = @props.clientPrograms.first()

				else
					matchingProgram = @props.clientPrograms.find (program) -> program.get('id') is userProgramId

					if matchingProgram?
						programId = matchingProgram
					else
						@programSelectionRequired = true


			return {
				title: @props.eventData.get('title')
				description: @props.eventData.get('description')
				program # TODO: Check this
			}

		propTypes: {
			eventData: React.PropTypes.instanceOf(Imm.Map).isRequired
			clientFileId: React.PropTypes.string.isRequired
			clientPrograms: React.PropTypes.instanceOf(Imm.List).isRequired
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