# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Generic timeSpan selector for events

Imm = require 'immutable'
Moment = require 'moment'

{TimestampFormat} = require './persist/utils'


load = (win) ->
	$ = win.jQuery
	React = win.React
	{PropTypes} = React
	R = React.DOM

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
			isDateSpan = !!@props.endTimestamp

			return {
				isDateSpan
				usesTimeOfDay: false
			}

		componentDidMount: ->
			# Initialize datepickers
			# TODO: Replace with datetimepicker components
			$startDate = $(@refs.startDate)
			$startTime = $(@refs.startTime)
			$endDate = $(@refs.endDate)
			$endTime = $(@refs.endTime)

			{startTimestamp, endTimestamp} = @props

			startDate = makeMoment(startTimestamp).toDate()
			endDate = if endTimestamp then makeMoment(endTimestamp).toDate() else null

			$startDate.datetimepicker({
				maxDate: endDate
				useCurrent: false
				format: 'Do MMM, \'YY'
				defaultDate: startDate
				widgetPositioning: {
					horizontal: 'right'
				}
			}).on 'dp.change', ({date}) =>
				$endDate.data('DateTimePicker').minDate(date)
				@_updateStartDate(date)

			$startTime.datetimepicker({
				useCurrent: false
				format: 'hh:mm a'
				defaultDate: startDate
				widgetPositioning: {
					horizontal: 'right'
				}
			}).on 'dp.change', ({date}) =>
				@_updateStartTime(date)


			$endDate.datetimepicker({
				minDate: startDate
				useCurrent: false
				format: 'Do MMM, \'YY'
				defaultDate: endDate
				widgetPositioning: {
					horizontal: 'right'
				}
			}).on 'dp.change', ({date}) =>
				$startDate.data('DateTimePicker').maxDate(date)
				@_updateEndDate(date)

			$endTime.datetimepicker({
				useCurrent: false
				format: 'hh:mm a'
				widgetPositioning: {
					horizontal: 'right'
				}
			}).on 'dp.change', ({date}) =>
				@_updateEndTime(date)

		toggleIsDateSpan: -> # public method
			isDateSpan = not @state.isDateSpan
			@setState {isDateSpan}

		render: ->
			R.div({className: 'timeSpanSelection'},
				R.div({className: 'dateGroup'},
					R.div({className: 'form-group date'},
						R.label({}, if @state.isDateSpan then "Start Date" else "Date")
						R.input({
							ref: 'startDate'
							className: 'form-control'
							type: 'text'
						})
					)
					R.div({className: "form-group timeOfDay #{showWhen @state.usesTimeOfDay}"},
						R.label({},
							R.span({onClick: @_toggleUsesTimeOfDay},
								FaIcon('clock-o')
								FaIcon('times')
							)
						)
						R.input({
							ref: 'startTime'
							className: 'form-control'
							type: 'text'
							placeholder: "00:00 --"
						})
					)
					R.div({className: "form-group useTimeOfDay #{showWhen not @state.usesTimeOfDay}"}
						R.button({
							className: 'btn btn-default'
							onClick: @_toggleUsesTimeOfDay
						}, FaIcon('clock-o'))
					)
				)
				R.div({className: "dateGroup #{showWhen @state.isDateSpan}"},
					R.div({
						className: 'form-group removeDateSpan'
					}
						R.span({onClick: @toggleIsDateSpan},
							FaIcon('arrow-right')
							FaIcon('times')
						)
					)
					R.div({className: 'form-group date'},
						R.label({}, "End Date")
						R.input({
							ref: 'endDate'
							className: 'form-control'
							type: 'text'
							placeholder: "Select date"
						})
					)
					R.div({className: "form-group timeOfDay #{showWhen @state.usesTimeOfDay}"},
						R.label({},
							R.span({onClick: @_toggleUsesTimeOfDay},
								FaIcon('clock-o')
								FaIcon('times')
							)
						)
						R.input({
							ref: 'endTime'
							className: 'form-control'
							type: 'text'
							placeholder: "00:00 --"
						})
					)
					R.div({className: "form-group useTimeOfDay #{showWhen not @state.usesTimeOfDay}"}
						R.button({
							className: 'btn btn-default'
							onClick: @_toggleUsesTimeOfDay
						}, FaIcon('clock-o'))
					)
				)
			)

		_toggleUsesTimeOfDay: ->
			usesTimeOfDay = not @state.usesTimeOfDay
			@setState {usesTimeOfDay}

		_updateStartTime: (startTime) ->
			startTimestamp = makeMoment(@props.startTimestamp)
			.set 'hour', startTime.hour()
			.set 'minute', startTime.minute()
			.format TimestampFormat

			@props.updateStartTimestamp(startTimestamp)

		_updateStartDate: (startDate) ->
			startTimestamp = makeMoment(@props.startTimestamp)
			.set 'date', startDate.date()
			.format TimestampFormat

			@props.updateStartTimestamp(startTimestamp)

		_updateEndTime: (startTime) ->
			endTimestamp = makeMoment(@props.endTimestamp)
			.set 'hour', endTime.hour()
			.set 'minute', endTime.minute()
			.format TimestampFormat

			@props.updateEndTimestamp(endTimestamp)

		_updateEndDate: (startDate) ->
			endTimestamp = makeMoment(@props.endTimestamp)
			.set 'date', startDate.date()
			.format TimestampFormat

			@props.updateEndTimestamp(endTimestamp)


	return TimeSpanSelection


module.exports = {load}