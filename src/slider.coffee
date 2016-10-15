# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Slider input component with range capabilities

_ = require 'underscore'
Moment = require 'moment'
Imm = require 'immutable'

Term = require './term'


load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	# TODO: Switch this out for a proper binding component
	Slider = React.createFactory React.createClass
		displayName: 'Slider'
		mixins: [React.addons.PureRenderMixin]

		componentDidUpdate: (oldProps, oldState) ->

			# Manually set slider value when @props.timeSpan changes
			newTimeSpan = @props.timeSpan
			xTicks = @props.xTicks

			if oldProps.xTicks.size isnt @props.xTicks.size
				@_initSlider()

			if not oldProps.timeSpan? and not oldProps.timeSpan.is newTimeSpan
				newValue = @_calculateIndexValues(newTimeSpan, xTicks)

				# Low value can't be bigger than the high value
				if newValue[0] > newValue[1]
					console.warn "Tried to make slider's minDate > maxDate, update cancelled", newValue[0], newValue[1]
					return

				# Ensure it's not same value as on the slider before updating
				# Comparing an array requires underscore
				if not _(newValue).isEqual @slider.slider('getValue')
					@slider.slider 'setValue', newValue

		componentDidMount: ->
			@_initSlider()

		componentWillUnmount: ->
			@slider.slider('destroy')

		_calculateIndexValues: (timeSpan, xTicks) ->
			start = timeSpan.get('start')
			end = timeSpan.get('end')

			matchingStartValue = xTicks.find (date) -> date.isSame(start)
			startIndex = xTicks.indexOf matchingStartValue

			matchingEndValue = xTicks.find (date) -> date.isSame(end)
			endIndex = xTicks.indexOf matchingEndValue

			indexValues = [startIndex, endIndex]
			return indexValues

		_initSlider: ->
			# Destroy it if already exists
			if @slider? then @slider.slider('destroy')

			{timeSpan, xTicks, formatter} = @props
			value = @_calculateIndexValues(timeSpan, xTicks)

			@slider = $(@refs.slider).slider({
				enabled: true
				tooltip: 'show'
				range: true
				min: 0
				max: xTicks.size - 1
				value
				formatter: ([start, end]) =>
					return unless start? and end?
					startTime = Moment(xTicks.get(start)).format('MMM Do')
					endTime = Moment(xTicks.get(end)).format('MMM Do')
					return "#{startTime} - #{endTime}"
			})

			# Register events
			@slider.on 'slideStop', @_onChange

		_onChange: (event) ->
			# Convert event value (string) to JS numerical array
			timeSpanArray = event.target.value.split(",")
			# Use index values to fetch moment objects from xTicks
			start = @props.xTicks.get Number(timeSpanArray[0])
			end = @props.xTicks.get Number(timeSpanArray[1])

			newTimeSpan = Imm.Map {start, end}
			@props.onChange newTimeSpan

		render: ->
			return R.input({ref: 'slider'})

module.exports = {load}