# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Date component for analysisTab which opens a bootbox datetimepicker

Moment = require 'moment'
_ = require 'underscore'

load = (win) ->
	$ = win.jQuery
	React = win.React
	R = React.DOM

	{FaIcon} = require('../utils').load(win)

	dateDisplayFormat = 'MMM Do - YYYY'
	defaultTimeSpan = {start: Moment(), end: Moment()}

	TimeSpanDate = React.createFactory React.createClass
		displayName: 'TimeSpanDate'
		mixins: [React.addons.PureRenderMixin]

		componentDidMount: ->
			# Assess min/maxDate based on which TimeSpanDate type
			if @props.type is 'start'
				minDate = @props.xTicks.first()
				maxDate = @props.timeSpan.end
			else
				minDate = @props.timeSpan.start
				maxDate = @props.xTicks.last()

			# Init datetimepicker
			$(@refs.hiddenDateTimePicker).datetimepicker({
				format: dateDisplayFormat
				useCurrent: false
				defaultDate: @props.date
				minDate
				maxDate

				toolbarPlacement: 'bottom'
				widgetPositioning: {
					vertical: 'bottom'
				}
			}).on 'dp.change', @_onChange

			@dateTimePicker = $(@refs.hiddenDateTimePicker).data('DateTimePicker')

		componentDidUpdate: (oldProps) ->
			# TODO: Refactor, test Perf
			# Compare timespans in {start, end} to oldProps
			if not oldProps.timeSpan.start.isSame(@props.timeSpan.start) and not @dateTimePicker.date().isSame(@props.timeSpan.start)
				startDate = @props.timeSpan.start

				if @props.type is 'start'
					# Update datetimepicker
					@dateTimePicker.date(startDate)
				else
					# 'end' TimeSpanDate changed
					@dateTimePicker.minDate(startDate)

			if not oldProps.timeSpan.end.isSame(@props.timeSpan.end) and not @dateTimePicker.date().isSame(@props.timeSpan.end)
				endDate = @props.timeSpan.end

				if @props.type is 'end'
					# Update datetimepicker
					@dateTimePicker.date(endDate)
				else
					# 'start' TimeSpanDate changed
					@dateTimePicker.maxDate(endDate)

		_onChange: (event) ->
			# Needs to be created in millisecond format to stay consistent
			newDate = Moment +Moment(event.target.value, dateDisplayFormat)
			@props.updateTimeSpanDate(newDate, @props.type)

		_toggleDateTimePicker: -> @dateTimePicker.toggle()

		render: ->
			formattedDate = @props.date.format(dateDisplayFormat)

			return R.div({className: 'timeSpanDate'},
				R.span({
					onClick: @_toggleDateTimePicker
					className: 'date'
				},
					R.input({
						ref: 'hiddenDateTimePicker'
						id: "datetimepicker-#{@props.type}"
					})
					R.span({}, formattedDate)
					R.span({}, FaIcon('caret-down'))
				)
			)

	return TimeSpanDate

module.exports = {load}