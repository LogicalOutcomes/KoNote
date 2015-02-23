load = (win) ->
	React = win.React
	R = React.DOM
	{FaIcon, showWhen} = require('./utils').load(win)

	MetricWidget = React.createFactory React.createClass
		render: ->
			return R.div({className: 'metricWidget'},
				(if @props.value?
					R.input({
						className: 'value circle'
						value: @props.value
						onChange: @_onChange
						placeholder: '__'
					})
				else
					R.div({className: 'icon circle'},
						FaIcon 'line-chart'
					)
				)
				R.div({className: 'name'},
					@props.name
				)
			)
		_onChange: (event) ->
			if @props.onChange
				@props.onChange event.target.value

	return MetricWidget

module.exports = {load}
