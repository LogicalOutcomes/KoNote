# Slider input component with range capabilities

load = (win) ->
	$ = win.jQuery
	React = win.React
	R = React.DOM

	Slider = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		getDefaultProps: ->
			return {
				value: [0, 0]
			}

		componentDidUpdate: (oldProps, oldState) ->
			# Re-init slider when ticks.length changes
			unless oldProps.ticks.length is @props.ticks.length
				@_initSlider()

		componentDidMount: ->
			@_initSlider()

		_initSlider: ->
			# Destroy it if already exists
			if @slider? then @slider.slider('destroy')

			console.log "Incoming timeSpan", @props.value

			@slider = $(@refs.slider).slider({
				enabled: true
				tooltip: 'show'
				range: true
				min: 0
				max: @props.ticks.length
				value: @props.value
				formatter: @props.formatter
			})

			# Register events
			@slider.on('slideStop', (event) => @props.onChange event)

		render: ->
			return R.input({ref: 'slider'})

module.exports = {load}