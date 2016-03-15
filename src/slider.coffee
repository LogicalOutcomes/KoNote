# Slider input component with range capabilities

load = (win) ->
	$ = win.jQuery
	React = win.React
	R = React.DOM

	Slider = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		componentDidUpdate: (oldProps, oldState) ->
			# Re-init slider when ticks.length changes
			unless oldProps.ticks.length is @props.ticks.length
				@slider.slider('destroy')
				@_initSlider()

		componentDidMount: ->
			console.log "@props.value", @props.value
			@_initSlider()

		_initSlider: ->			

			@slider = $(@refs.slider).slider({
					enabled: true
					tooltip: 'show'
					range: @props.isRange or false
					min: 0
					max: @props.ticks.length
					value: @props.value or [0, @props.ticks.length]
					formatter: @props.formatter or ((value) -> value)
				})

			# Register events
			@slider.on('slideStop', (event) => @props.onChange event)

		render: ->
			return R.input({ref: 'slider'})

module.exports = {load}