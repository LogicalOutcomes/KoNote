# Slider input component with range capabilities

# Options:
# 	isEnabled: boolean
# 	tooltip: boolean
# 	isRange: boolean
# 	defaultValue: []
# 	ticks: []
# 	onChange: ->
# 	formatter: (value) ->

load = (win) ->
	$ = win.jQuery
	React = win.React
	R = React.DOM

	Slider = React.createFactory React.createClass
			mixins: [React.addons.PureRenderMixin]

			getInitialState: ->
				slider: null

			componentDidMount: ->
				@setState {
					slider: $(@refs.slider.getDOMNode()).slider({
						enabled: @props.isEnabled
						tooltip: if @props.tooltip then 'show' else 'hide'
						range: @props.isRange or false
						min: @props.minValue or 0
						max: @props.maxValue or @props.ticks.length
						value: @props.defaultValue
						formatter: @props.formatter or ((value) -> value)
					})
				}, =>
					@state.slider.on('slideStop', (event) => @props.onChange event)

			render: ->
				return R.input({ref: 'slider'})

module.exports = {load}