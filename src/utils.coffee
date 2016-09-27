# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

_ = require 'underscore'
Moment = require 'moment'

{TimestampFormat} = require './persist'
{CustomError} = require './persist/utils'
Config = require './config'

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
	FaIcon = (name, props = {}) ->
		# if the name is an extension, return an appropriate icon (paperclip if unknown)
		if /[.]/.test(name)
			switch name.toLowerCase()
				when '.avi' then name = 'file-video-o'
				when '.bmp' then name = 'image'
				when '.doc' then name = 'file-word-o'
				when '.docx' then name = 'file-word-o'
				when '.jpeg' then name = 'image'
				when '.jpg' then name = 'image'
				when '.mov' then name = 'file-video-o'
				when '.ogg' then name = 'file-video-o'
				when '.mp3' then name = 'file-audio-o'
				when '.mp4' then name = 'file-video-o'
				when '.pdf' then name = 'file-pdf-o'
				when '.png' then name = 'image'
				when '.rtf' then name = 'file-text-o'
				when '.tga' then name = 'image'
				when '.tiff' then name = 'image'
				when '.txt' then name = 'file-text-o'
				when '.wav' then name = 'file-audio-o'
				when '.xls' then name = 'file-excel-o'
				when '.xlsx' then name = 'file-excel-o'
				when '.zip' then name = 'file-archive-o'
				else name = 'paperclip'
		
		className = "fa fa-#{name}"

		# Extend with className from props if any
		if props.className?
			className += " #{props.className}"

		props.className = className

		return R.i(props)

	# A convenience method for opening a new window
	# Callback function (optional) provides window context as argument
	openWindow = (params, cb=(->)) ->
		width = 1200
		height = 700

		if nw.Screen.screens[0].work_area.width < 1200
			width = nw.Screen.screens[0].work_area.width
		if nw.Screen.screens[0].work_area.height < 700
			height = nw.Screen.screens[0].work_area.height

		Gui.Window.open 'src/main.html?' + $.param(params), {
			focus: false
			show: false
			width
			height
			min_width: 640
			min_height: 640
			icon: "src/icon.png"
		}, cb

	renderName = (name) ->
		result = [name.get('first')]

		if name.get('middle')
			result.push name.get('middle')

		result.push name.get('last')

		return result.join ' '

	# Returns the clientFileId with label
	# Setting 2nd param as true returns nothing if id is empty/nonexistent
	renderRecordId = (id, hidden) ->
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
		unless text?
			console.warn "renderLineBreaks received no input: ", text
			return ""

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
		.delete('_dirPath')

	formatTimestamp = (timestamp, customFormat = '') ->
		return Moment(timestamp, TimestampFormat).format(customFormat or Config.timestampFormat)

	capitalize = (word) ->
    return word.charAt(0).toUpperCase() + word.slice(1)

	# Ensures that `text` does not exceed `maxLength` by replacing excess
	# characters with an ellipsis character.
	truncateText = (maxLength, text) ->
		if text.length <= maxLength
			return text

		return text[...(maxLength - 1)] + '…'

	makeMoment = (timestamp) -> Moment timestamp, TimestampFormat

	##### Convenience methods for fetching data from a progNote

	getUnitIndex = (progNote, unitId) ->
		result = progNote.get('units')
		.findIndex (unit) =>
			return unit.get('id') is unitId

		if result is -1
			throw new Error "could not find unit with ID #{JSON.stringify unitId}"

		return result

	getPlanSectionIndex = (progNote, unitIndex, sectionId) ->
		result = progNote.getIn(['units', unitIndex, 'sections'])
		.findIndex (section) =>
			return section.get('id') is sectionId

		if result is -1
			throw new Error "could not find unit with ID #{JSON.stringify sectionId}"

		return result

	getPlanTargetIndex = (progNote, unitIndex, sectionIndex, targetId) ->
		result = progNote.getIn(['units', unitIndex, 'sections', sectionIndex, 'targets'])
		.findIndex (target) =>
			return target.get('id') is targetId

		if result is -1
			throw new Error "could not find target with ID #{JSON.stringify targetId}"

		return result

	return {
		CustomError
		executeIfFunction
		FaIcon
		openWindow
		renderLineBreaks
		renderName
		renderRecordId
		showWhen
		stripMetadata
		formatTimestamp
		capitalize
		truncateText
		makeMoment
		getUnitIndex
		getPlanSectionIndex
		getPlanTargetIndex
	}

module.exports = {
	load
	CustomError # for modules that can't provide a window object
}
