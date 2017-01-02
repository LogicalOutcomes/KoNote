# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Date component for analysisTab which opens a bootbox datetimepicker

Moment = require 'moment'
_ = require 'underscore'
Imm = require 'immutable'


Config = require '../config'


load = (win) ->
	$ = win.jQuery
	React = win.React
	R = React.DOM

	{FaIcon} = require('../utils').load(win)

	TimeSpanToolbar = React.createFactory React.createClass
		displayName: 'TimeSpanDate'
		mixins: [React.addons.PureRenderMixin]

		render: ->

			spanSize = @props.timeSpan.get('end').diff(@props.timeSpan.get('start'), 'days')

			return R.div({className: 'timeSpanToolbar'},
				R.div({className: 'btn-group btn-group-sm'},
					R.div({
						className: 'btn btn-default'
						onClick: @_shiftTimeSpanRange.bind(null, @props.lastDay, @props.firstDay, 'past')
					},
						FaIcon('caret-left')
					)
					R.div({
						className: [
							'btn'
							'selected' if spanSize is 1
						].join ' '
						onClick: @_setTimeSpanRange.bind(null, @props.lastDay, 'day')
					},
						"Day"
					)
					R.div({
						className: [
							'btn'
							'selected' if spanSize is 7
						].join ' '
						onClick: @_setTimeSpanRange.bind(null, @props.lastDay, 'week')
					},
						"Week"
					)
					R.div({
						className: [
							'btn'
							'selected' if spanSize is 30 or spanSize is 31
						].join ' '
						onClick: @_setTimeSpanRange.bind(null, @props.lastDay, 'month')
					},
						"Month"
					)
					R.div({
						className: [
							'btn'
							'selected' if spanSize is 365 or spanSize is 366
						].join ' '
						onClick: @_setTimeSpanRange.bind(null, @props.lastDay, 'year')
					},
						"Year"
					)
					R.div({
						className: [
							'btn'
							'selected' if spanSize is @props.dayRange
						].join ' '
						onClick: @_showAllData.bind(null, @props.lastDay, @props.firstDay)
					},
						"All"
					)

					R.div({
						className: 'btn btn-default'
						onClick: @_shiftTimeSpanRange.bind(null, @props.lastDay, @props.firstDay, 'future')
					},
						FaIcon('caret-right')
					)
				)
			)

		_showAllData: (lastDay, firstDay) ->
			timeSpan = Imm.Map {
				start: firstDay
				end: lastDay.clone().add(1, 'day')
			}

			@props.updateTimeSpan(timeSpan)

		_setTimeSpanRange: (lastDay, unit) ->
			end = lastDay.clone().add(1, 'days')
			start = lastDay.clone().subtract(1, unit).add(1,'days')
			timeSpan = Imm.Map {
				start
				end
			}

			@props.updateTimeSpan(timeSpan)

		_shiftTimeSpanRange: (lastDay, firstDay, direction) ->
			start = @props.timeSpan.get('start').clone()
			end = @props.timeSpan.get('end').clone()
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
			if end.isAfter(lastDay.add(1, 'day')) or start.isBefore(firstDay)
				console.warn "Attempting to shift spanRange outside of data limits."
				return
			timeSpan = Imm.Map {
				start
				end
			}

			@props.updateTimeSpan(timeSpan)

	return TimeSpanToolbar

module.exports = {load}