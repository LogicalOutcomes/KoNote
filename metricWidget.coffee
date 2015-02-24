load = (win) ->
	$ = win.jQuery
	React = win.React
	R = React.DOM
	{FaIcon, renderLineBreaks, showWhen} = require('./utils').load(win)

	MetricWidget = React.createFactory React.createClass
		componentDidMount: ->
			tooltipContent = R.div({className: 'tooltipContent'},
				renderLineBreaks @props.definition
			)
			$(@refs.name.getDOMNode()).tooltip {
				html: true
				title: React.renderToString tooltipContent
			}
		render: ->
			isEditable = @props.isEditable isnt false

			return R.div({className: 'metricWidget'},
				(if @props.value?
					R.input({
						className: 'value circle'
						value: @props.value
						onChange: @_onChange
						placeholder: (if isEditable
							'__'
						else
							'--'
						)
						disabled: isEditable is false
					})
				else
					R.div({className: 'icon circle'},
						FaIcon 'line-chart'
					)
				)
				R.div({className: 'name', ref: 'name'},
					@props.name
				)
			)
		_onChange: (event) ->
			if @props.onChange
				@props.onChange event.target.value

	return MetricWidget

module.exports = {load}
