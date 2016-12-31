# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Tab layer component for creating/managing event types

Async = require 'async'
Imm = require 'immutable'

Persist = require './persist'
Term = require './term'
{EventTypeColors} = require './colors'


load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	# TODO: Refactor to single require
	{BootstrapTable, TableHeaderColumn} = win.ReactBootstrapTable
	BootstrapTable = React.createFactory BootstrapTable
	TableHeaderColumn = React.createFactory TableHeaderColumn

	CrashHandler = require('./crashHandler').load(win)
	Dialog = require('./dialog').load(win)
	OpenDialogLink = require('./openDialogLink').load(win)
	ColorKeyBubble = require('./colorKeyBubble').load(win)
	ColorKeySelection = require('./colorKeySelection').load(win)
	DialogLayer = require('./dialogLayer').load(win)

	{FaIcon, showWhen, stripMetadata, renderName} = require('./utils').load(win)


	EventTypeManagerTab = React.createFactory React.createClass
		displayName: 'EventTypeManagerTab'
		mixins: [React.addons.PureRenderMixin]
		# TODO: propTypes

		getInitialState: ->
			return {
				dataIsReady: false
				eventTypes: Imm.List()
				displayInactive: false
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
							Bootbox.alert "Please check your network connection and try again."
							return

						CrashHandler.handle err
						return

					@setState {
						dataIsReady: true
						eventTypes
					}

		render: ->
			hasData = not @state.eventTypes.isEmpty()


			eventTypes = @state.eventTypes

			unless @state.displayInactive
				eventTypes = @state.eventTypes.filter (eventType) ->
					eventType.get('status') is 'default'

			inactiveEventTypes = @state.eventTypes.filter (eventType) ->
				eventType.get('status') isnt "default"

			hasInactiveEventTypes = not inactiveEventTypes.isEmpty()


			return R.div({className: 'eventTypeManagerTab'},
				R.div({className: 'header'},
					R.h1({},
						R.div({className: 'optionsMenu'},
							OpenDialogLink({
								className: 'btn btn-primary'
								dialog: CreateEventTypeDialog
								onSuccess: @_addNewEventType
								data:
									eventTypes: @state.eventTypes
							},
								FaIcon('plus')
								" New #{Term 'Event Type'}"
							)
							(if hasInactiveEventTypes
								R.div({className: 'toggleInactive'},
									R.label({},
										"Show inactive (#{inactiveEventTypes.size})"
										R.input({
											type: 'checkbox'
											checked: @state.displayInactive
											onClick: @_toggleDisplayInactive
										})
									)
								)
							)
						)

						Term 'Event Types'
					)

				)
				R.div({className: 'main'},
					(if @state.dataIsReady
						(if hasData
							R.div({className: 'responsiveTable animated fadeIn'},
								DialogLayer({
									ref: 'dialogLayer'
									eventTypes: @state.eventTypes
									onSuccess: @_modifyEventType
								},
									BootstrapTable({
										data: eventTypes.toJS()
										keyField: 'id'
										bordered: false
										options: {
											defaultSortName: 'name'
											defaultSortOrder: 'asc'
											onRowClick: ({id}) =>
												@refs.dialogLayer.open ModifyEventTypeDialog, {eventTypeId: id}

											noDataText: "No #{Term 'event types'} to display"
										}
										trClassName: (row) -> 'inactive' if row.status isnt 'default'
									},
										TableHeaderColumn({
											dataField: 'colorKeyHex'
											className: 'colorKeyColumn'
											columnClassName: 'colorKeyColumn'
											dataFormat: (colorKeyHex) -> ColorKeyBubble({colorKeyHex})
										})
										TableHeaderColumn({
											dataField: 'name'
											className: 'nameColumn'
											columnClassName: 'nameColumn'
											dataSort: true
										}, "Type Name")
										TableHeaderColumn({
											dataField: 'description'
											className: 'descriptionColumn'
											columnClassName: 'descriptionColumn'
										}, "Description")
										TableHeaderColumn({
											dataField: 'status'
											className: [
												'statusColumn'
												'rightPadding' if @state.displayInactive
											].join ' '
											columnClassName: [
												'statusColumn'
												'rightPadding' if @state.displayInactive
											].join ' '
											dataSort: true
											hidden: not @state.displayInactive
											headerAlign: 'right'
											dataAlign: 'right'
										}, "Status")
									)
								)
							)
						else
							R.div({className: 'noData'},
								R.span({className: 'animated fadeInUp'},
									"No #{Term 'event types'} exist yet"
								)
							)
						)
					)
				)
			)
		_toggleDisplayInactive: ->
			displayInactive = not @state.displayInactive
			@setState {displayInactive}

		_addNewEventType: (newEventType) ->
			eventTypes = @state.eventTypes.push newEventType
			@setState {eventTypes}

		_modifyEventType: (modifiedEventType) ->
			originalEventType = @state.eventTypes.find (eventType) ->
				eventType.get('id') is modifiedEventType.get('id')

			eventTypeIndex = @state.eventTypes.indexOf originalEventType
			eventTypes = @state.eventTypes.set(eventTypeIndex, modifiedEventType)

			@setState {eventTypes}


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
			return @_getEventType().toObject()

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
					R.div({className: 'form-group'},
						R.label({}, "Status"),
						R.div({className: 'btn-toolbar'},
							R.button({
								className:
									if @state.status is 'default'
										'btn btn-default active'
									else 'btn btn-default'
								onClick: @_updateStatus
								value: 'default'

								},
							"Default"
							)
							R.button({
								className:
									'btn btn-' + if @state.status is 'cancelled'
										'active'
									else
										'default'
								onClick: @_updateStatus
								value: 'cancelled'

								},
							"Deactivated"
							)
						)
					)
					R.hr({})
					R.div({className: 'btn-toolbar pull-right'},
						R.button({
							className: 'btn btn-default'
							onClick: @props.onCancel
						}, "Cancel")
						R.button({
							className: 'btn btn-primary'
							disabled: (
								not @state.name or not @state.description or not @state.colorKeyHex
							) or not @_hasChanges()
							onClick: @_submit
						},
							"Save Changes"
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

		_updateStatus: (event) ->
			@setState {status: event.target.value}

		_getEventType: ->
			@props.eventTypes.find (eventType) => eventType.get('id') is @props.eventTypeId

		_buildModifiedEventTypeObject: ->
			originalEventType = @_getEventType()

			return Imm.fromJS({
				id: originalEventType.get('id')
				name: @state.name
				description: @state.description
				colorKeyHex: @state.colorKeyHex
				status: @state.status
			})

		_hasChanges: ->
			originalEventType = @_getEventType()
			modifiedEventType = @_buildModifiedEventTypeObject()
			return not Imm.is originalEventType, modifiedEventType

		_submit: (event) ->
			event.preventDefault()

			modifiedEventType = @_buildModifiedEventTypeObject()

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
