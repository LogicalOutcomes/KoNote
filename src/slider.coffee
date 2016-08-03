# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Slider input component with range capabilities
_ = require 'underscore'
Term = require './term'

load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	Slider = React.createFactory React.createClass
		displayName: 'Slider'
		mixins: [React.addons.PureRenderMixin]

		componentDidUpdate: (oldProps, oldState) ->
			# Re-init slider when ticks.length changes
			unless oldProps.xTicks.size is @props.xTicks.size
				@_initSlider()

			# Manually set slider value when @props.timeSpan changes
			if oldProps.timeSpan isnt @props.timeSpan
				newValue = @_calculateIndexValues(@props.timeSpan)

				# Ensure it's not same value as on the slider before updating
				# Comparing an array requires underscore
				if not _(newValue).isEqual @slider.slider('getValue')
					@slider.slider 'setValue', newValue

		componentDidMount: ->
			@_initSlider()

		_calculateIndexValues: (timeSpan) ->

			start = timeSpan.get('start')
			end = timeSpan.get('end')

			matchingStartValue = @props.xTicks.find (date) -> date.isSame(start)
			startIndex = @props.xTicks.indexOf matchingStartValue

			matchingEndValue = @props.xTicks.find (date) -> date.isSame(end)
			endIndex = @props.xTicks.indexOf matchingEndValue

			indexValues = [startIndex, endIndex]

			return indexValues


		_initSlider: ->
			# Destroy it if already exists
			if @slider? then @slider.slider('destroy')

			value = @_calculateIndexValues(@props.timeSpan)

			@slider = $(@refs.slider).slider({
				enabled: true
				tooltip: 'show'
				range: true
				min: 0
				max: @props.xTicks.size - 1
				value
				formatter: @props.formatter
			})

			# Register events
			@slider.on 'slideStop', @props.onChange

		render: ->
			return R.input({ref: 'slider'})

module.exports = {load}