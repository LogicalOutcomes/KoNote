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
	TimeSpanDate = require('./clientFilePage/timeSpanDate').load(win)
	ExpandingTextArea = require('./expandingTextArea').load(win)
	EventTypesDropdown = require('./eventTypesDropdown').load(win)
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
				eventType.get('id') is progEvent.get('eventTypeId')


			return (switch format
				when 'large', 'print'
					FullWidget({
						progEvent
						eventType
						eventTypes
						format
						isEditing
						updateProgEvent: @_updateProgEvent
					})
				when 'small'
					SmallWidget({
						progEvent
						eventType
					})
				else
					throw new Error "Unknown progEventsWidget format: #{format}"
			)

		_updateProgEvent: (property, event) ->
			value = (switch property
				when 'title', 'description'
					event.target.value
				when 'startTimestamp'
					event.get('start')
				when 'endTimestamp'
					event.get('end')
				when 'eventType'
					event
				else
					throw new Error "Unrecognized property: #{property}"
			)

			progEvent = @props.progEvent.set property, value
			@props.updateProgEvent(progEvent)


	FullWidget = ({progEvent, eventType, eventTypes, format, isEditing, updateProgEvent}) ->
		progEventId = progEvent.get('id')

		startMoment = makeMoment progEvent.get('startTimestamp')

		endMoment = if progEvent.get('endTimestamp')
			makeMoment(progEvent.get('endTimestamp'))
		else
			null

		timeSpan = Imm.Map {
			start: startMoment
			end: endMoment
		}

		return R.div({className: "progEventWidget fullWidget #{format}"},
			R.h5({className: 'title'},
				FaIcon('calendar')
				' '
				(if isEditing
					R.input({
						className: 'form-control'
						value: progEvent.get('title')
						onChange: updateProgEvent.bind null, 'title'
					})
				else
					progEvent.get('title')
				)
			)
			R.div({className: 'description'},
				(if isEditing
					ExpandingTextArea({
						value: progEvent.get('description')
						onChange: updateProgEvent.bind null, 'description'
					})
				else
					renderLineBreaks progEvent.get('description')
				)

				R.div({className: 'date'},
					(if isEditing
						R.div({},
							TimeSpanDate({
								type: 'start'
								date: startMoment
								timeSpan
								updateTimeSpanDate: updateProgEvent.bind null, 'startTimestamp'
							})
							(if endMoment
								TimeSpanDate({
									type: 'end'
									date: endMoment
									timeSpan
									updateTimeSpanDate: updateProgEvent.bind null, 'endTimestamp'
								})
							)
						)
					else
						renderTimeSpan progEvent.get('startTimestamp'), progEvent.get('endTimestamp')
					)
				)
			)
			(unless progEvent or progEvents.isEmpty()
				R.div({},
					"Type: "

					(if isEditing
						EventTypesDropdown({

						})
					else
						R.span({
							style:
								borderBottom: "2px solid #{eventType.get('colorKeyHex')}"
						},
							eventType.get('name')
						)
					)
				)
			)
		)




	SmallWidget = ({progEvent, eventType}) ->
		eventDate = renderTimeSpan progEvent.get('startTimestamp'), progEvent.get('endTimestamp')
		tooltipText = "#{eventDate}\n{title}"

		return WithTooltip({
			title: tooltipText
			placement: 'auto'
			showTooltip: true
		},
			R.div({
				className: 'progEventWidget smallWidget'
				style:
					background: eventType.get('colorKeyHex') if eventType?
			},
				FaIcon('calendar')
				' '
				title
			)
		)



	return ProgEventWidget

module.exports = {load}
