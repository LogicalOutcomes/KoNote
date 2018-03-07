# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Buttons for analysisTab which modify the time span in predefined increments

Moment = require 'moment'
Imm = require 'immutable'

load = (win) ->
	$ = win.jQuery
	React = win.React
	{PropTypes} = React
	R = React.DOM

	{FaIcon} = require('../utils').load(win)

	TimeSpanToolbar = React.createFactory React.createClass
		displayName: 'TimeSpanToolbar'
		mixins: [React.addons.PureRenderMixin]

		propTypes: {
			updateTimeSpan: PropTypes.func.isRequired
			timeSpan: PropTypes.instanceOf(Imm.Map).isRequired
			lastDay: PropTypes.instanceOf(Moment).isRequired
			firstDay: PropTypes.instanceOf(Moment).isRequired
			dayRange: PropTypes.number.isRequired
		}

		render: ->
			spanSize = @props.timeSpan.get('end').diff(@props.timeSpan.get('start'), 'days')

			return R.div({className: 'timeSpanToolbar'},
				R.div({className: 'btn-group btn-group-sm'},
					R.button({
						className: 'btn arrow'
						onClick: @_shiftTimeSpanRange.bind(null, @props.lastDay, @props.firstDay, 'past')
						disabled: not @_rangeIsValid(null, null, 'past')
					},
						FaIcon('caret-left')
					)

					# ToDo: refactor these buttons into a component. They are all pretty similar.
					R.div({
						className: [
							'btn'
							'selected' if spanSize is 1
						].join ' '
						onClick: @_setTimeSpanRange.bind(null, 1, 'day')
						disabled: not @_rangeIsValid(1, 'day')
					},
						R.span({className: 'buttonWord'},
							"Day"
						)
						R.span({className: 'buttonLetter'},
							"D"
						)
					)
					R.div({
						className: [
							'btn'
							'selected' if spanSize is 7
						].join ' '
						onClick: @_setTimeSpanRange.bind(null, 1, 'week')
						disabled: not @_rangeIsValid(1, 'week')
					},
						R.span({className: 'buttonWord'},
							"Week"
						)
						R.span({className: 'buttonLetter'},
							"W"
						)
					)
					R.button({
						className: [
							'btn'
							'selected' if spanSize is 30 or spanSize is 31
						].join ' '
						onClick: @_setTimeSpanRange.bind(null, 1, 'month')
						disabled: not @_rangeIsValid(1, 'month')
					},
						R.span({className: 'buttonWord'},
							"1 Month"
						)
						R.span({className: 'buttonLetter'},
							"1M"
						)
					)
					R.button({
						className: [
							'btn'
							'selected' if spanSize > 88 && spanSize < 93
						].join ' '
						onClick: @_setTimeSpanRange.bind(null, 3, 'months')
						disabled: not @_rangeIsValid(3, 'months')
					},
						R.span({className: 'buttonWord'},
							"3 Months"
						)
						R.span({className: 'buttonLetter'},
							"3M"
						)
					)

					R.button({
						className: [
							'btn'
							'selected' if spanSize is 365 or spanSize is 366
						].join ' '
						onClick: @_setTimeSpanRange.bind(null, 1, 'year')
						disabled: not @_rangeIsValid(1, 'year')
					},
						R.span({className: 'buttonWord'},
							"Year"
						)
						R.span({className: 'buttonLetter'},
							"Y"
						)
					)
					R.button({
						className: [
							'btn'
							'selected' if spanSize is @props.dayRange
						].join ' '
						onClick: @_showAllData.bind(null, @props.lastDay, @props.firstDay)
					},
						"All"
					)
					R.button({
						className: 'btn arrow'
						onClick: @_shiftTimeSpanRange.bind(null, @props.lastDay, @props.firstDay, 'future')
						disabled: not @_rangeIsValid(null, null, 'future')
					},
						FaIcon('caret-right')
					)
				)
			)

		_rangeIsValid: (value, unit, direction = null) ->
			if direction is 'future'
				spanSize = @props.timeSpan.get('end').diff(@props.timeSpan.get('start'), 'days')
				start = @props.timeSpan.get('start').clone().add(spanSize, 'days')
				end = @props.timeSpan.get('end').clone().add(spanSize, 'days')
			else if direction is 'past'
				spanSize = @props.timeSpan.get('end').diff(@props.timeSpan.get('start'), 'days')
				start = @props.timeSpan.get('start').clone().subtract(spanSize, 'days')
				end = @props.timeSpan.get('end').clone().subtract(spanSize, 'days')
			else
				end = @props.timeSpan.get('end').clone()
				start = end.clone().subtract(value, unit)

			if end.isAfter(@props.lastDay.clone().add(1, 'day')) or start.isBefore(@props.firstDay)
				return false
			return true

		_showAllData: (lastDay, firstDay) ->
			timeSpan = Imm.Map {
				start: firstDay
				end: lastDay.clone().add(1, 'day')
			}

			@props.updateTimeSpan(timeSpan)

		_setTimeSpanRange: (value, unit) ->
			unless @_rangeIsValid value, unit
				return

			end = @props.timeSpan.get('end').clone()
			start = end.clone().subtract(value, unit)
			timeSpan = Imm.Map {
				start
				end
			}

			@props.updateTimeSpan(timeSpan)

		_shiftTimeSpanRange: (lastDay, firstDay, direction) ->
			start = @props.timeSpan.get('start').clone().startOf('day');
			end = @props.timeSpan.get('end').clone().endOf('day');
			difference = end.diff(start, 'days') + 1

			if direction is 'future'
				start.add(difference, 'days')
				end.add(difference, 'days')
			else if direction is 'past'
				start.subtract(difference, 'days')
				end.subtract(difference, 'days')
			else
				console.warn "Unknown span shift direction"
				return

			# unless end date is after lastDay or start is before first day
			if end.isAfter(lastDay.clone().add(1, 'day')) or start.clone().isBefore(firstDay)
				console.warn "Attempting to shift spanRange outside of data limits."
				return
			timeSpan = Imm.Map {
				start
				end
			}

			@props.updateTimeSpan(timeSpan)

	return TimeSpanToolbar

module.exports = {load}