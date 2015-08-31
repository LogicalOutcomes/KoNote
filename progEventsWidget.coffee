# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# React widget to drop in wherever events should be displayed
# 2 display formats: large and small

Moment = require 'moment'
Persist = require './persist'

load = (win) ->
	$ = win.jQuery
	React = win.React
	R = React.DOM
	{FaIcon, openWindow, renderLineBreaks, showWhen} = require('./utils').load(win)
	
	niceDate = (start, end) ->
		startDate = Moment(start, Persist.TimestampFormat).format 'MMMM D, YYYY'
		startTime = Moment(start, Persist.TimestampFormat).format 'HH:mm'
		endDate = Moment(end, Persist.TimestampFormat).format 'MMMM D, YYYY'
		endTime = Moment(end, Persist.TimestampFormat).format 'HH:mm'
		if (startDate is endDate) and (startTime is '00:00') and (endTime is '23:59')
			# single day
			eventDate = startDate
		else if endDate is 'Invalid date'
			# single day + time
			eventDate = [startDate, ' at ', startTime]
		else
			# multiple dates
			eventDate = [startDate, ' - ', endDate]
		eventDate
	
	progEventWidget = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]
		componentDidMount: ->
			tooltipContent = R.div({},
				niceDate @props.start, @props.end
				R.br()
				@props.description
			)
			$(@refs.name.getDOMNode()).tooltip {
				html: true
				title: React.renderToString tooltipContent
				placement: 'auto'
				# required to stop tooltip from being obstructed by menu
				viewport: $(@refs.name.getDOMNode()).parent()
			}
		render: ->
			format = @props.format
			title = @props.title
			description = @props.description
			eventDate = niceDate @props.start, @props.end
			
			return R.div({className: 'progEventsWidget'},
				if format is 'large'
					R.div({
						className: format, ref: 'name'
					},
						title,
						R.br(),
						eventDate,
						R.br(),
						renderLineBreaks description
					)
				else
					R.div({
						className: format, ref: 'name'
					},
						R.div({
							className: 'icon'
						},
							FaIcon 'calendar'
							' '
							title
						)
					)
			)
	
	return progEventWidget

module.exports = {load}
