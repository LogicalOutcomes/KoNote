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
			return R.div({className: 'timeSpanToolbar'},
				R.div({className: 'btn-group'},
					R.button({
						onClick: @_shiftTimeSpanRange.bind(null, @props.lastDay, @props.firstDay, 'past')
					},
						FaIcon('caret-left')
					)
					R.button({
						onClick: @_setTimeSpanRange.bind(null, @props.lastDay, 'day')
					},
						"Day"
					)
					R.button({
						onClick: @_setTimeSpanRange.bind(null, @props.lastDay, 'week')
					},
						"Week"
					)
					R.button({
						onClick: @_setTimeSpanRange.bind(null, @props.lastDay, 'month')
					},
						"Month"
					)
					R.button({
						onClick: @_setTimeSpanRange.bind(null, @props.lastDay, 'year')
					},
						"Year"
					)
					R.button({
						onClick: @_shiftTimeSpanRange.bind(null, @props.lastDay, @props.firstDay, 'future')
					},
						FaIcon('caret-right')
					)
				)
			)

		_setTimeSpanRange: (lastDay, unit) ->
			end = lastDay.clone().add(1, 'days')
			start = lastDay.clone().subtract(1, unit)
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

			# unless end date is after lastDay or start is before first day
			unless end.isAfter(lastDay.add(1, 'day')) or start.isBefore(firstDay)
				timeSpan = Imm.Map {
					start
					end
				}

				@props.updateTimeSpan(timeSpan)

	return TimeSpanToolbar

module.exports = {load}