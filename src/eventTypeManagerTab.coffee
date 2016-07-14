# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

Async = require 'async'
Imm = require 'immutable'

Persist = require './persist'
Config = require './config'
Term = require './term'
{EventTypeColors} = require './colors'

load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	CrashHandler = require('./crashHandler').load(win)
	Dialog = require('./dialog').load(win)
	Spinner = require('./spinner').load(win)
	OrderableTable = require('./orderableTable').load(win)
	OpenDialogLink = require('./openDialogLink').load(win)
	ExpandingTextArea = require('./expandingTextArea').load(win)
	ColorKeyBubble = require('./colorKeyBubble').load(win)
	ColorKeySelection = require('./colorKeySelection').load(win)

	{FaIcon, showWhen, stripMetadata, renderName} = require('./utils').load(win)


	EventTypeManagerTab = React.createFactory React.createClass
		displayName: 'EventTypeManagerTab'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				eventTypes: null
			}

		componentWillMount: ->
			eventTypeHeaders = null
			eventTypes = null

			Async.series [
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
						if err instanceof Persist.IOError
							console.error err
							console.error err.stack
							@setState {loadErrorType: 'io-error'}
							return

						CrashHandler.handle err
						return

					@setState {eventTypes}

		render: ->
			return R.div({className: 'eventTypeManagerTab'},
				R.div({className: 'header'},
					R.h1({}, Term 'Event Types')
				)
				R.div({className: 'main'},
					OrderableTable({
						tableData: @state.eventTypes
						noMatchesMessage: "No #{Term 'event'} types defined yet"
						sortByData: ['name']
						columns: [
							{
								name: "Colour Key"
								nameIsVisible: false
								dataPath: ['colorKeyHex']
								cellClass: 'colorKeyCell'
								value: (dataPoint) ->
									ColorKeyBubble({colorKeyHex: dataPoint.get('colorKeyHex')})
							}
							{
								name: "Type Name"
								dataPath: ['name']
								cellClass: 'nameCell'
							}
							{
								name: "Description"
								dataPath: ['description']
								value: (dataPoint) ->
									description = dataPoint.get('description')

									if description.length > 60
										return description.substr(0, 59) + ' . . .'
									else
										return description
							}
							{
								name: "Options"
								nameIsVisible: false
								cellClass: 'optionsCell'
								buttons: [
									{
										className: 'btn btn-warning'
										text: null
										icon: 'wrench'
										dialog: ModifyEventTypeDialog
										data: {
											onSuccess: @_modifyEventType
											eventTypes: @state.eventTypes
										}
									}
								]
							}
						]
					})
				)
				R.div({className: 'optionsMenu'},
					OpenDialogLink({
						className: 'btn btn-lg btn-primary'
						dialog: CreateEventTypeDialog
						onSuccess: @_addNewEventType
						data:
							eventTypes: @state.eventTypes
					},
						FaIcon('plus')
						" New #{Term 'Event Type'}"
					)
				)
			)

		_addNewEventType: (newEventType) ->
			@setState {eventTypes: @state.eventTypes.push newEventType}

		_modifyEventType: (modifiedEventType) ->
			originalEventType = @state.eventTypes
			.find (eventType) -> eventType.get('id') is modifiedEventType.get('id')

			eventTypeIndex = @state.eventTypes.indexOf originalEventType

			@setState {eventTypes: @state.eventTypes.set(eventTypeIndex, modifiedEventType)}


	CreateEventTypeDialog = React.createFactory React.createClass
		displayName: 'CreateEventTypeDialog'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				name: ''
				colorKeyHex: null
				description: ''
			}

		componentDidMount: ->
			@refs.eventTypeName.focus()

		render: ->
			return Dialog({
				ref: 'dialog'
				title: "Create New #{Term 'Event Type'}"
				onClose: @props.onCancel
			},
				R.div({className: 'createEventTypeDialog'},
					R.div({className: 'form-group'},
						R.label({}, "Name")
						R.input({
							className: 'form-control'
							ref: 'eventTypeName'
							placeholder: "Specify #{Term 'event type'} name"
							value: @state.name
							onChange: @_updateName
							style:
								borderColor: @state.colorKeyHex
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "Color Key")
						ColorKeySelection({
							colors: EventTypeColors
							data: @props.data.eventTypes
							selectedColorKeyHex: @state.colorKeyHex
							onSelect: @_updateColorKeyHex
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "Description")
						R.textarea({
							className: 'form-control'
							placeholder: "Describe the #{Term 'event type'}"
							value: @state.description
							onChange: @_updateDescription
							rows: 3
						})
					)
					R.div({className: 'btn-toolbar'},
						R.button({
							className: 'btn btn-default'
							onClick: @props.onCancel
						}, "Cancel")
						R.button({
							className: 'btn btn-success'
							disabled: not @state.name or not @state.description or not @state.colorKeyHex
							onClick: @_submit
						},
							"Create #{Term 'Event Type'}"
						)
					)
				)
			)

		_updateName: (event) ->
			@setState {name: event.target.value}

		_updateDescription: (event) ->
			@setState {description: event.target.value}

		_updateColorKeyHex: (colorKeyHex) ->
			@setState {colorKeyHex}

		_buildEventTypeObject: ->
			return Imm.fromJS {
				name: @state.name
				colorKeyHex: @state.colorKeyHex
				description: @state.description
				status: 'default'
			}

		_submit: (event) ->
			event.preventDefault()

			newEventType = @_buildEventTypeObject()
			@_createEventType(newEventType)

		_createEventType: (newEventType) ->
			@refs.dialog.setIsLoading true

			# Create the new eventType
			ActiveSession.persist.eventTypes.create newEventType, (err, result) =>
				@refs.dialog.setIsLoading(false) if @refs.dialog?

				if err
					CrashHandler.handle err
					return

				# Deliver directly to manager, no top-level listeners available (yet)
				@props.onSuccess result
				@props.onClose()


	ModifyEventTypeDialog = React.createFactory React.createClass
		displayName: 'ModifyEventTypeDialog'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				name: @props.rowData.get('name')
				colorKeyHex: @props.rowData.get('colorKeyHex')
				description: @props.rowData.get('description')
			}

		componentDidMount: ->
			@refs.eventTypeName.focus()

		render: ->
			return Dialog({
				ref: 'dialog'
				title: "Modify #{Term 'Event Type'}"
				onClose: @props.onCancel
			},
				R.div({className: 'createEventTypeDialog'},
					R.div({className: 'form-group'},
						R.label({}, "Name")
						R.input({
							className: 'form-control'
							ref: 'eventTypeName'
							placeholder: "Specify #{Term 'event type'} name"
							value: @state.name
							onChange: @_updateName
							style:
								borderColor: @state.colorKeyHex
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "Colour Key")
						ColorKeySelection({
							colors: EventTypeColors
							onSelect: @_updateColorKeyHex
							data: @props.eventTypes
							selectedColorKeyHex: @state.colorKeyHex
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "Description")
						R.textarea({
							className: 'form-control'
							placeholder: "Describe the #{Term 'event type'}"
							value: @state.description
							onChange: @_updateDescription
							rows: 3
						})
					)
					R.div({className: 'btn-toolbar'},
						R.button({
							className: 'btn btn-default'
							onClick: @props.onCancel
						}, "Cancel")
						R.button({
							className: 'btn btn-success'
							disabled: (
								not @state.name or not @state.description or not @state.colorKeyHex
							) or not @_hasChanges()
							onClick: @_submit
						},
							"Finished"
						)
					)
				)
			)

		_updateName: (event) ->
			@setState {name: event.target.value}

		_updateDescription: (event) ->
			@setState {description: event.target.value}

		_updateColorKeyHex: (colorKeyHex) ->
			@setState {colorKeyHex}

		_buildModifiedEventTypeObject: ->
			return Imm.fromJS({
				id: @props.rowData.get('id')
				name: @state.name
				description: @state.description
				colorKeyHex: @state.colorKeyHex
				status: @props.rowData.get('status')
			})

		_hasChanges: ->
			return not Imm.is @props.rowData, @_buildModifiedEventTypeObject()

		_submit: (event) ->
			event.preventDefault()

			modifiedEventType = @_buildModifiedEventTypeObject()
			@_modifyEventType(modifiedEventType)

		_modifyEventType: (modifiedEventType) ->
			@refs.dialog.setIsLoading(true)

			# Update the eventType revision, and close
			ActiveSession.persist.eventTypes.createRevision modifiedEventType, (err, result) =>
				@refs.dialog.setIsLoading(false) if @refs.dialog?

				if err
					CrashHandler.handle err
					return

				# Deliver directly to manager, no top-level listeners available (yet)
				@props.onSuccess result
				@props.onClose()


	return EventTypeManagerTab

module.exports = {load}
