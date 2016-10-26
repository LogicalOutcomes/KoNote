# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Generic timeSpan selector for events

Imm = require 'immutable'
Moment = require 'moment'

Config = require './config'
{TimestampFormat} = require './persist/utils'


load = (win) ->
	$ = win.jQuery
	React = win.React
	{PropTypes} = React
	R = React.DOM

	WithTooltip = require('./withTooltip').load(win)
	{FaIcon, renderName, showWhen, formatTimestamp, makeMoment} = require('./utils').load(win)


	TimeSpanSelection = React.createFactory React.createClass
		displayName: 'TimeSpanSelection'

		propTypes: {
			startTimestamp: PropTypes.instanceOf(Moment)
			endTimestamp: PropTypes.instanceOf(Moment)
			updateStartTimestamp: PropTypes.func.isRequired
			updateEndTimestamp: PropTypes.func.isRequired
		}

		getInitialState: ->
			# TODO: Work this logic out within render, feeds datepicker components
			{startTimestamp, endTimestamp} = @props

			# (endTimestamp won't exist for point-events)
			endTimestampExists = !!endTimestamp

			startMoment = makeMoment(startTimestamp)
			endMoment = if endTimestampExists then makeMoment(endTimestamp) else null

			# Work out whether usesTimeOfDay (full day and daySpan don't count)
			isFromStartOfDay = startMoment.isSame startMoment.clone().startOf('day')
			isToEndOfDay = endTimestampExists and endMoment.clone().isSame endMoment.endOf('day')
			isFromStartToEndOfDay = isFromStartOfDay and isToEndOfDay

			isSameDay = endTimestampExists and startMoment.clone().isSame endMoment, 'day'

			# These are cases where we don't want to start with a timeOfDay
			isOneFullDay = isSameDay and isFromStartToEndOfDay
			isSpanOfDays = endTimestampExists and not isSameDay

			# Finally, declare how to set our initial state
			isDateSpan = not isOneFullDay and isSpanOfDays
			usesTimeOfDay = not isOneFullDay and not isFromStartToEndOfDay

			return {
				isDateSpan
				usesTimeOfDay
			}

		componentDidMount: ->
			$startDate = $(@refs.startDate)
			$startTime = $(@refs.startTime)
			$endDate = $(@refs.endDate)
			$endTime = $(@refs.endTime)

			{startTimestamp, endTimestamp} = @props

			startDate = makeMoment(startTimestamp).toDate()
			endDate = if endTimestamp then makeMoment(endTimestamp).toDate() else null

			# Make sure these datetimepickers stay within the frame
			leftPositioning = {
				horizontal: 'left'
				vertical: 'top'
			}

			rightPositioning = {
				horizontal: 'right'
				vertical: 'top'
			}


			# Init all the datetimepickers, link with update functions

			$startDate.datetimepicker({
				maxDate: endDate
				useCurrent: false
				format: Config.dateFormat
				defaultDate: startDate
				widgetPositioning: leftPositioning
			}).on 'dp.change', ({date}) =>
				$endDate.data('DateTimePicker').minDate(date)
				@_updateStartDate(date)

			@startDate = $startDate.data('DateTimePicker')


			$startTime.datetimepicker({
				useCurrent: false
				format: Config.timeFormat
				defaultDate: startDate
				widgetPositioning: leftPositioning
			}).on 'dp.change', ({date}) =>
				@_updateStartTime(date)

			@startTime = $startTime.data('DateTimePicker')


			$endDate.datetimepicker({
				minDate: startDate
				useCurrent: false
				format: Config.dateFormat
				defaultDate: endDate
				widgetPositioning: rightPositioning
			}).on 'dp.change', ({date}) =>
				$startDate.data('DateTimePicker').maxDate(date)
				@_updateEndDate(date)

			@endDate = $endDate.data('DateTimePicker')


			$endTime.datetimepicker({
				useCurrent: false
				format: Config.timeFormat
				defaultDate: endDate
				widgetPositioning: rightPositioning
			}).on 'dp.change', ({date}) =>
				@_updateEndTime(date)

			@endTime = $endTime.data('DateTimePicker')


		render: ->
			# Titles reflect the nature of the start/end timestamps
			startDateTitle = if @state.isDateSpan and @state.usesTimeOfDay
				"Start Date & Time"
			else if @state.isDateSpan and not @state.usesTimeOfDay
				"Start Date"
			else if not @state.isDateSpan and not @state.usesTimeOfDay
				"Date (full day)"
			else
				"Date & Time"

			endDateTitle = if @state.usesTimeOfDay
				"End Date & Time"
			else
				"End Date"


			return R.div({className: 'timeSpanSelection form-group'},

				R.section({},
					R.div({},
						R.label({}, startDateTitle)
						R.div({className: 'startDate'},
							R.div({className: 'inputContainer'},
								R.input({
									ref: 'startDate'
									className: 'form-control'
									type: 'text'
								})
							)
							(if not @state.usesTimeOfDay
								R.div({className: 'buttonContainer'},
									WithTooltip({
										title: "Add time of day"
										placement: 'top'
									},
										R.button({
											className: 'btn btn-default timeOfDayToggleButton'
											onClick: @_toggleUsesTimeOfDay
										},
											FaIcon('clock-o')
										)
									)
								)
							)
						)
						R.div({className: "startTime #{showWhen @state.usesTimeOfDay}"},
							R.div({className: 'inputContainer'},
								R.input({
									ref: 'startTime'
									className: 'form-control'
									type: 'text'
									placeholder: "00:00 --"
								})
							)
							R.div({className: 'buttonContainer'},
								WithTooltip({
									title: "Remove time of day"
									placement: 'top'
								},
									R.button({
										className: 'btn btn-default timeOfDayToggleButton'
										onClick: @_toggleUsesTimeOfDay
									},
										FaIcon('minus')
									)
								)
							)
						)
					)
					## Raw view of props, for debugging purposes
					# R.div({},
					# 	formatTimestamp makeMoment @props.startTimestamp
					# 	R.br()
					# 	if @props.endTimestamp then formatTimestamp makeMoment @props.endTimestamp else "NONE"
					# )
				)

				R.section({className: "arrow #{showWhen @state.isDateSpan}"},
					FaIcon('arrow-right')
				)

				R.section({},
					R.div({className: "endDateContainer #{showWhen @state.isDateSpan}"},
						WithTooltip({
							title: "Remove end date"
							placement: 'top'
						},
							FaIcon('times', {onClick: @_toggleIsDateSpan})
						)
						R.label({}, endDateTitle)
						R.div({className: 'endDate'},
							R.div({className: 'inputContainer'},
								R.input({
									ref: 'endDate'
									className: 'form-control'
									type: 'text'
								})
							)
						)
						R.div({className: 'endTime'},
							R.div({className: "inputContainer #{showWhen @state.usesTimeOfDay}"},
								R.input({
									ref: 'endTime'
									className: 'form-control'
									type: 'text'
									placeholder: "00:00 --"
								})
							)
						)
					)

					R.span({
						className: "addEndDateButton #{showWhen not @state.isDateSpan}"
						onClick: @_toggleIsDateSpan
					},
						R.div({},
							R.label({}, "Add End Date")
							R.div({},
								FaIcon('plus')
							)
						)
					)
				)
			)

		_toggleUsesTimeOfDay: ->
			usesTimeOfDay = not @state.usesTimeOfDay

			startMoment = @_getStartMoment()
			endMoment = @_getEndMoment()

			if usesTimeOfDay
				# ADDING timeOfDay
				@_updateStartTime startMoment

				if not @state.isDateSpan
					@props.updateEndTimestamp('')

			else
				# REMOVING timeOfDay
				if @state.isDateSpan
					endOfDay = endMoment.clone().endOf 'day'
					startOfDay = startMoment.clone().startOf 'day'

					@_updateStartTime startOfDay
					@_updateEndDate endOfDay
					@_updateEndTime endOfDay
				else
					endOfDay = startMoment.clone().endOf 'day'
					startOfDay = endMoment.clone().startOf 'day'

					@_updateStartTime startOfDay
					@_updateEndDate endOfDay
					@_updateEndTime endOfDay


			@setState {usesTimeOfDay}

		_toggleIsDateSpan: ->
			isDateSpan = not @state.isDateSpan

			startMoment = @_getStartMoment()
			endMoment = @_getEndMoment()

			if isDateSpan
				# ADDING dateSpan

				if @state.usesTimeOfDay
					# When using time of day, default to same as startTime
					@_updateEndTime startMoment
				else
					# Otherwise, we assume it's a span of days, so use end of day
					@_updateEndTime endMoment.clone().endOf 'day'

				# End date defaults to 1 day after startDay
				@_updateEndDate startMoment.clone().add(1, 'day')

			else
				# REMOVING dateSpan
				if @state.usesTimeOfDay
					# Point event requires no endTimestamp
					@props.updateEndTimestamp('')
				else
					# Reset endTimestamp to end of same day
					endOfStartDay = startMoment.clone().endOf 'day'
					@_updateEndDate endOfStartDay
					# @_updateEndTime endOfStartDay


			@setState {isDateSpan}

		_updateStartTime: (startTime) ->
			startTimestamp = @_getStartMoment()
			.set 'hour', startTime.hour()
			.set 'minute', startTime.minute()

			@startTime.date startTimestamp

			@props.updateStartTimestamp startTimestamp.format(TimestampFormat)

		_updateStartDate: (startDate) ->
			startTimestamp = @_getStartMoment()
			.set 'date', startDate.date()

			@startDate.date startTimestamp

			@props.updateStartTimestamp startTimestamp.format(TimestampFormat)

		_updateEndTime: (endTime) ->
			date = @_getEndMoment()

			endTimestamp = date
			.set 'hour', endTime.hour()
			.set 'minute', endTime.minute()

			@endTime.date endTimestamp

			@props.updateEndTimestamp endTimestamp.format(TimestampFormat)

		_updateEndDate: (endDate) ->
			date = @_getEndMoment()

			endTimestamp = date
			.set 'date', endDate.date()

			@endDate.date endTimestamp

			@props.updateEndTimestamp endTimestamp.format(TimestampFormat)

		_getStartMoment: ->
			makeMoment @props.startTimestamp

		_getEndMoment: ->
			if not @props.endTimestamp
				return makeMoment @props.startTimestamp

			makeMoment @props.endTimestamp


	return TimeSpanSelection


module.exports = {load}