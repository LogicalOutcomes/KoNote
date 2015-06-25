# Prints only the specified containing div

# Takes the className or ID of the parent div as an argument
# and then prints nothing but that div's contents

load = (win) ->
	$ = win.jQuery
	React = win.React
	R = React.DOM
	{FaIcon, openWindow} = require('./utils').load(win)

	PrintButton = React.createFactory React.createClass
		render: ->
			return R.button({
				className: 'btn btn-info'
				onClick: @_printDiv
				ref: 'printButton'
			},
				if @props.title then @props.title else "Print"
				FaIcon('print')
			)
		_printDiv: ->
			openWindow {
				page: 'printPreview'
				dataSet: JSON.stringify(@props.dataSet)
			}

	return PrintButton

module.exports = {load}
