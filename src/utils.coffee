# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

Config = require './config'
_ = require 'underscore'

# This class allows new error types to be created easily without breaking stack
# traces, toString, etc.
#
# Example:
# 	class MyError extends CustomError
#
# MyError will accept a single, optional argument `message`.
#
# Example:
# 	class MyError2 extends CustomError
# 		constructor: (message, anotherArgument) ->
# 			super message # must call superclass constructor
# 			@anotherArgument = anotherArgument
#
# MyError2 will accept two mandatory arguments: `message` and `anotherArgument`.
class CustomError extends Error
	constructor: (message) ->
		@name = @constructor.name
		@message = message
		Error.captureStackTrace @, @constructor

load = (win) ->
	$ = win.jQuery
	React = win.React
	R = React.DOM
	Gui = win.require 'nw.gui'

	# Execute variable as a function if it is one
	executeIfFunction = (variable, arg) ->
		if typeof variable is 'function'
			if arg?
				return variable arg
			else
				return variable()
		else
			return variable

	# Shortcut for using Font Awesome icons in React
	FaIcon = (name, customProps) ->
		properties = {className: "fa fa-#{name}"}
		if customProps?
			# Extend in any custom settings
			_.extend properties, customProps

		return R.i(properties)

	# A convenience method for opening a new window
	openWindow = (params) ->
		Gui.Window.open 'main.html?' + $.param(params), {
			focus: true
			toolbar: false
			width: 1000
			height: 700
			icon: "icon.png"
		}

	renderName = (name) ->
		result = []
		result.push name.get('first')

		if name.has('middle') and name.get('middle').size
			result.push name.get('middle')

		result.push name.get('last')

		return result.join ' '

	# Returns the clientFileId with label
	# Setting 2nd param as true returns nothing if id is empty/nonexistent
	renderFileId = (id, hidden) ->
		result = []
		result.push Config.clientFileRecordId.label

		if not id or id.length is 0
			if hidden then return null
			result.push "(n/a)"
		else
			result.push id

		return result.join ' '

	# Converts line breaks to React <br> tags and trims leading or trailing whitespace
	renderLineBreaks = (text) ->
		lines = text.trim()
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

	# Persistent objects come with metadata that makes it difficult to compare
	# revisions (e.g. timestamp).  This method removes those attributes.
	stripMetadata = (persistObj) ->
		return persistObj
		.delete('revisionId')
		.delete('author')
		.delete('timestamp')

	# Ensures that `text` does not exceed `maxLength` by replacing excess
	# characters with an ellipsis character.
	truncateText = (maxLength, text) ->
		if text.length <= maxLength
			return text

		return text[...(maxLength - 1)] + '…'

	return {
		CustomError
		executeIfFunction
		FaIcon
		openWindow
		renderLineBreaks
		renderName
		renderFileId
		showWhen
		stripMetadata
		truncateText
	}

module.exports = {
	load
	CustomError # for modules that can't provide a window object
}
