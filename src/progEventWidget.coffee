# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# React widget to drop in wherever events should be displayed
# Formats: 'small', 'large', and 'print'

Moment = require 'moment'
Imm = require 'immutable'

Persist = require './persist'
Config = require './config'


load = (win) ->
	$ = win.jQuery
	React = win.React
	{PropTypes} = React
	R = React.DOM

	WithTooltip = require('./withTooltip').load(win)
	ExpandingTextArea = require('./expandingTextArea').load(win)
	EventTypesDropdown = require('./eventTypesDropdown').load(win)
	TimeSpanSelection = require('./timeSpanSelection').load(win)
	{FaIcon, openWindow, renderLineBreaks, makeMoment, renderTimeSpan} = require('./utils').load(win)


	ProgEventWidget = React.createFactory React.createClass
		displayName: 'ProgEventWidget'
		mixins: [React.addons.PureRenderMixin]

		propTypes: {
			format: PropTypes.string
			isEditing: PropTypes.bool
			onChange: PropTypes.func
			progEvent: PropTypes.instanceOf(Imm.Map).isRequired
			eventTypes: PropTypes.instanceOf(Imm.List)
		}

		getDefaultProps: -> {
			isEditing: false
			eventTypes: Imm.List()
		}

		render: ->
			{progEvent, eventTypes, isEditing, format} = @props

			eventType = eventTypes.find (eventType) ->
				eventType.get('id') is progEvent.get('typeId')


			return (switch format
				when 'large', 'print'
					FullWidget({
						progEvent
						eventType
						eventTypes
						format
						isEditing
						updateProperty: @_updateProperty
						updateTimestamps: @_updateTimestamps
					})
				when 'small'
					SmallWidget({
						progEvent
						eventType
						format
					})
				else
					throw new Error "Unknown progEventsWidget format: #{format}"
			)

		_updateProperty: (property, event) ->
			# TODO: Make this less weird
			value = switch property
				when 'title', 'description'
					event.target.value
				when 'typeId'
					event
				else
					throw new Error "Unrecognized property: #{property}"

			progEvent = @props.progEvent.set property, value

			# Reset the title when a typeId is indicated
			if property is 'typeId' and !!value
				progEvent = progEvent.set 'title', ''

			@props.updateProgEvent(progEvent)

		_updateTimestamps: ({startTimestamp, endTimestamp}) ->
			progEvent = @props.progEvent

			if startTimestamp?
				progEvent = progEvent.set 'startTimestamp', startTimestamp
			if endTimestamp?
				progEvent = progEvent.set 'endTimestamp', endTimestamp

			@props.updateProgEvent(progEvent)


	FullWidget = React.createFactory React.createClass
		displayName: 'FullWidget'
		mixins: [React.addons.PureRenderMixin]

		render: ->
			{progEvent, eventType, eventTypes, format, isEditing, updateProperty, updateTimestamps} = @props
			progEventId = progEvent.get('id')

			canEditEventTypes = isEditing and not eventTypes.isEmpty()
			hasEventType = !!eventType
			hasTitle = !!progEvent.get('title')
			hasDescription = !!progEvent.get('description')


			return R.div({className: "progEventWidget fullWidget #{format}"},
				R.div({className: 'eventTypeTitleContainer'},
					R.span({
						className: 'iconContainer'
						style: {
							background: eventType.get('colorKeyHex') if hasEventType
						}
					},
						FaIcon('calendar', {
							style:
								color: 'white' if hasEventType
						})
					)

					(if canEditEventTypes
						R.div({className: 'eventType'},
							R.div({},
								"Type: "
								EventTypesDropdown({
									eventTypes
									selectedEventType: eventType
									onSelect: updateProperty.bind null, 'typeId'
								})
							)
						)
					)

					R.div({className: 'title'},
						(if isEditing and (hasTitle or not hasEventType)
							R.input({
								className: 'form-control'
								value: progEvent.get('title')
								onChange: updateProperty.bind null, 'title'
								placeholder: "Title"
							})
						else if not isEditing
							R.span({},
								progEvent.get('title') or EventTypeName(eventType)

								(if hasTitle and hasEventType
									R.span({className: 'eventTypeName'},
										" ("
										EventTypeName(eventType)
										")"
									)
								)
							)
						)
					)
				)

				(if hasDescription or isEditing
					R.div({className: 'description'},
						(if isEditing
							ExpandingTextArea({
								value: progEvent.get('description')
								onChange: updateProperty.bind null, 'description'
								placeholder: "Description"
							})
						else
							R.span({},
								renderLineBreaks progEvent.get('description')
							)
						)
					)
				)

				R.div({className: 'date'},
					(if isEditing
						TimeSpanSelection({
							ref: 'timeSpanSelection'
							startTimestamp: progEvent.get('startTimestamp')
							endTimestamp: progEvent.get('endTimestamp')
							updateTimestamps
						})
					else
						renderTimeSpan progEvent.get('startTimestamp'), progEvent.get('endTimestamp')
					)
				)
			)




	SmallWidget = ({progEvent, eventType, format}) ->
		eventDate = renderTimeSpan progEvent.get('startTimestamp'), progEvent.get('endTimestamp')
		title = progEvent.get('title')
		tooltipText = eventDate

		return WithTooltip({
			title: tooltipText
			placement: 'auto'
			showTooltip: true
		},
			R.div({
				className: "progEventWidget #{format}"
				style:
					background: eventType.get('colorKeyHex') if eventType?
			},
				FaIcon('calendar')
				' '
				title
			)
		)


	EventTypeName = (eventType) ->
		R.span({
			style:
				borderBottom: "2px solid #{eventType.get('colorKeyHex')}"
		},
			eventType.get('name')
		)



	return ProgEventWidget

module.exports = {load}
