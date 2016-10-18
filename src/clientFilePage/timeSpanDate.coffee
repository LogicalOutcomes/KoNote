# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Date component for analysisTab which opens a bootbox datetimepicker

Moment = require 'moment'
_ = require 'underscore'

Config = require '../config'


load = (win) ->
	$ = win.jQuery
	React = win.React
	R = React.DOM

	{FaIcon} = require('../utils').load(win)


	# TODO: Switch this out for a proper binding component
	TimeSpanDate = React.createFactory React.createClass
		displayName: 'TimeSpanDate'
		mixins: [React.addons.PureRenderMixin]

		componentDidMount: ->
			@_init()

		_init: ->
			if @dateTimePicker? then @dateTimePicker.destroy()

			# Assess min/maxDate based on which TimeSpanDate type
			if @props.type is 'start'
				minDate = @props.xTicks.first()
				maxDate = @props.timeSpan.get('end')
			else
				minDate = @props.timeSpan.get('start')
				maxDate = @props.xTicks.last()

			# Init datetimepicker
			$(@refs.hiddenDateTimePicker).datetimepicker({
				format: Config.dateFormat
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
			# TODO: Handle start/end logic in analysis, use generic component

			if @props.xTicks.size isnt oldProps.xTicks.size
				firstDay = @props.xTicks.first()
				lastDay = @props.xTicks.last()

				if @props.type is 'start'
					@dateTimePicker.minDate firstDay
					@dateTimePicker.maxDate @props.timeSpan.get('end')
				else
					@dateTimePicker.minDate @props.timeSpan.get('start')
					@dateTimePicker.maxDate lastDay


			startPropHasChanged = not oldProps.date.get('start').isSame(@props.timeSpan.get('start'))
			startDateIsNew = not @dateTimePicker.date().isSame(@props.timeSpan.get('start'), 'day')

			if startPropHasChanged
				startDate = @props.timeSpan.get('start')

				if @props.type is 'start'
					# Update 'start' datetimepicker
					@dateTimePicker.date startDate
				else
					# Catch bad updates
					if startDate.isAfter @dateTimePicker.maxDate()
						console.warn "Tried to make minDate > maxDate, update cancelled"
						return

					# For 'end', just adjust the minDate
					@dateTimePicker.minDate startDate


			endPropHasChanged = not oldProps.timeSpan.get('end').isSame @props.timeSpan.get('end')
			endDateIsNew = not @dateTimePicker.date().isSame @props.timeSpan.get('end')

			if endPropHasChanged
				endDate = @props.timeSpan.get('end')

				if @props.type is 'end'
					# Update 'end' datetimepicker
					@dateTimePicker.date endDate
				else
					# Catch bad updates
					if endDate.isBefore @dateTimePicker.minDate()
						console.warn "Tried to make maxDate < minDate, update cancelled"
						return

					# For 'start', just adjust the maxDate
					@dateTimePicker.maxDate endDate

		_onChange: (event) ->
			# Needs to be created in millisecond format to stay consistent
			newDate = Moment +Moment(event.target.value, Config.dateFormat).startOf('day')
			timeSpan = @props.timeSpan.set(@props.type, newDate)

			@props.updateTimeSpanDate timeSpan

		_toggleDateTimePicker: -> @dateTimePicker.toggle()

		render: ->
			return null unless @props.date

			formattedDate = @props.date.format(Config.dateFormat)

			return R.div({className: 'timeSpanDate'},
				R.span({
					onClick: @_toggleDateTimePicker
					className: 'date'
					style:
						position: 'relative'
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