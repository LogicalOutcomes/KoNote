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
	{FaIcon, openWindow, renderLineBreaks, makeMoment, renderTimeSpan} = require('./utils').load(win)

	# TODO: Rename to singular
	ProgEventsWidget = React.createFactory React.createClass
		displayName: 'ProgEventsWidget'
		mixins: [React.addons.PureRenderMixin]

		propTypes: {
			format: PropTypes.string
			isEditable: PropTypes.bool
			progEvent: PropTypes.instanceOf(Imm.Map).isRequired
			eventType: PropTypes.instanceOf(Imm.Map).isRequired
		}

		getDefaultProps: -> {
			isEditable: false
		}

		render: ->
			{progEvent, eventType, isEditable, format} = @props

			startMoment = makeMoment startTimestamp
			endMoment = if endTimestamp then makeMoment(endTimestamp) else null

			return (switch format
				when 'large', 'print'
					FullWidget({
						progEvent
						eventType
						format
						isEditable
					})
				when 'small'
					SmallWidget({
						progEvent
						eventType
					})
				else
					throw new Error "Unknown progEventsWidget format: #{format}"
			)


	FullWidget = ({progEvent, eventType, format, isEditable}) ->
		progEventId = progEvent.get('id')

		return R.div({className: "progEventsWidget fullWidget #{format}"},
			R.h5({className: 'title'},
				FaIcon('calendar')
				' '
				progEvent.get('title')
			)
			R.div({className: 'description'},
				renderLineBreaks progEvent.get('description')

				R.div({className: 'date'},
					renderTimeSpan progEvent.get('startTimestamp'), progEvent.get('endTimestamp')
				)
			)
			(if eventType? and not eventType.isEmpty()
				R.div({},
					"Type: "
					R.span({
						style:
							borderBottom: "2px solid #{eventType.get('colorKeyHex')}"
					},
						eventType.get('name')
					)
				)
			)
		)


	SmallWidget = ({progEvent eventType}) ->
		tooltipText = "#{eventDate}\n{title}"

		return WithTooltip({
			title: tooltipText
			placement: 'auto'
			showTooltip: true
		},
			R.div({
				className: 'progEventsWidget smallWidget'
				style:
					background: eventType.get('colorKeyHex') if eventType?
			},
				FaIcon('calendar')
				' '
				title
			)
		)


	return ProgEventsWidget

module.exports = {load}
