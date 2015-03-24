load = (win) ->
	$ = win.jQuery
	React = win.React
	R = React.DOM
	Gui = win.require 'nw.gui'

	# Shortcut for using Font Awesome icons in React
	FaIcon = (name) ->
		return R.i({className: "fa fa-#{name}"})

	# A convenience method for opening a new window
	openWindow = (params) ->
		Gui.Window.open 'main.html?' + $.param(params), {
			focus: true
			toolbar: false
			width: 1000
			height: 700
		}

	renderName = (name) ->
		result = []
		result.push name.get('first')

		if name.has('middle')
			result.push name.get('middle')

		result.push name.get('last')

		return result.join ' '

	# Converts line breaks to React <br> tags
	# It might make sense to trim the text first to avoid leading or trailing
	# whitespace.
	renderLineBreaks = (text) ->
		lines = text
		.replace(/\r\n/g, '\n') # Windows -> Unix
		.replace(/\r/g, '\n') # old Mac -> Unix
		.split('\n')

		result = []

		for line, lineIndex in lines
			if lineIndex > 0
				result.push R.br()

			if line.trim()
				result.push line

		return result

	# Useful for conditionally hiding React components
	showWhen = (condition) ->
		if condition
			return ''

		return 'hide'

	# Ensures that `text` does not exceed `maxLength` by replacing excess
	# characters with an ellipsis character.
	truncateText = (maxLength, text) ->
		if text.length <= maxLength
			return text

		return text[...(maxLength - 1)] + '…'

	return {
		FaIcon
		openWindow
		renderLineBreaks
		renderName
		showWhen
		truncateText
	}

module.exports = {load}
