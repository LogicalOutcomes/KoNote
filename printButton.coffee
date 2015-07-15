# Prints only the specified containing div

# Takes the className or ID of the parent div as an argument
# and then prints nothing but that div's contents

load = (win) ->
	$ = win.jQuery
	React = win.React
	R = React.DOM
	{FaIcon, openWindow, showWhen} = require('./utils').load(win)

	PrintButton = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]
		render: ->
			return R.button({
				className: [
					'printButton'
					'btn btn-default'
					'disabled' if @props.disabled
				].join ' '
				onClick: @_printDiv if not @props.tooltip or not @props.tooltip.show
				ref: 'printButton'
			},
				R.span({}, if not @props.iconOnly then "Print")
				FaIcon('print')
			)
		componentDidUpdate: ->
			if @props.tooltip
				if @props.tooltip.show
					$(@getDOMNode()).tooltip {
						html: true
						placement: @props.tooltip.placement
						title: @props.tooltip.title
					}
				else
					$(@getDOMNode()).tooltip 'destroy'
		_printDiv: ->
			openWindow {
				page: 'printPreview'
				dataSet: JSON.stringify(@props.dataSet)
			}

	return PrintButton

module.exports = {load}
