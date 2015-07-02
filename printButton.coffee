# Prints only the specified containing div

# Takes the className or ID of the parent div as an argument
# and then prints nothing but that div's contents

load = (win) ->
	$ = win.jQuery
	React = win.React
	R = React.DOM
	{FaIcon, openWindow, showWhen} = require('./utils').load(win)

	PrintButton = React.createFactory React.createClass
		render: ->
			return R.button({
				className: [
					'printButton'
					'btn btn-default'
					showWhen @props.isVisible
				].join ' '
				onClick: @_printDiv
				ref: 'printButton'
			},
				R.span({}, "Print")
				FaIcon('print')
			)
		_printDiv: ->
			openWindow {
				page: 'printPreview'
				dataSet: JSON.stringify(@props.dataSet)
			}

	return PrintButton

module.exports = {load}
