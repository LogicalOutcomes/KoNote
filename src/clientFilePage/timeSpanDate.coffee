# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Date component for analysisTab which opens a bootbox datetimepicker
# TODO: Replace with simpler react datetimepicker component

Moment = require 'moment'
_ = require 'underscore'

Config = require '../config'


load = (win) ->
	$ = win.jQuery
	React = win.React
	R = React.DOM

	{FaIcon} = require('../utils').load(win)


	TimeSpanDate = React.createFactory React.createClass
		displayName: 'TimeSpanDate'
		mixins: [React.addons.PureRenderMixin]

		componentDidMount: ->
			@_init()

		_init: ->
			if @dateTimePicker? then @dateTimePicker.destroy()

			# Assess min/maxDate
			if @props.xTicks?
				minDate = @props.xTicks.first()
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
			# TODO: couldnt this evaluate to true even if the xticks changed?
			if @props.xTicks and @props.xTicks.size isnt oldProps.xTicks.size
				@dateTimePicker.minDate @props.xTicks.first()
				@dateTimePicker.maxDate @props.xTicks.last()

			# update the start or end date
			@dateTimePicker.date @props.timeSpan.get(@props.type)

		_onChange: (event) ->
			newDate = Moment(event.date)
			oldDate = Moment(event.oldDate)

			# Prevent redundant update when new day is same as before
			if newDate.isSame @props.timeSpan.get(@props.type), 'day'
				return
			# Discard invalid dates
			else if @props.type is 'start' and newDate.isAfter @props.timeSpan.get('end')
				$(@refs.hiddenDateTimePicker).data('DateTimePicker').date(oldDate)
				return
			else if @props.type is 'end' and newDate.isBefore @props.timeSpan.get('start')
				$(@refs.hiddenDateTimePicker).data('DateTimePicker').date(oldDate)
				return
			else
				timeSpan = @props.timeSpan.set(@props.type, newDate)
				@props.updateTimeSpan(timeSpan)

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
					R.span({className: 'dateText'}, formattedDate)
					R.span({className: 'dateIcon'}, FaIcon('calendar'))
					R.span({}, FaIcon('caret-down'))
				)
			)

	return TimeSpanDate

module.exports = {load}