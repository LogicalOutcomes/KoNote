# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Set of frequently-used utilities used all around the app

_ = require 'underscore'
Moment = require 'moment'

{TimestampFormat} = require './persist'
{CustomError} = require './persist/utils'
Config = require './config'


load = (win) ->
	$ = win.jQuery
	React = win.React
	R = React.DOM

	# return a list of unsafe file extensions
	blockedExtensions = [
		'.action',
		'.app',
		'.application',
		'.bat',
		'.bin',
		'.cmd',
		'.com',
		'.command',
		'.cpl',
		'.csh',
		'.esf',
		'.exe',
		'.gadget',
		'.hta',
		'.inf',
		'.jar',
		'.js',
		'.jse',
		'.lnk',
		'.msc',
		'.msi',
		'.msp',
		'.osx',
		'.ps1',
		'.ps2',
		'.psc1',
		'.psc2',
		'.reg',
		'.scf',
		'.scr',
		'.vb',
		'.vbs',
		'.vbscript',
		'.workflow',
		'.ws'
	]

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
	openWindow = (params, options = {}, cb=(->)) ->
		width = 1200
		height = 700
		screenWidth = nw.Screen.screens[0].work_area.width
		screenHeight = nw.Screen.screens[0].work_area.height

		if options instanceof Function then cb = options

		if options.maximize
			width = screenWidth
			height = screenHeight
		else
			if screenWidth < 1200
				width = screenWidth
			if screenHeight < 700
				height = screenHeight

		switch params.page
			when 'clientSelection'
				page = 'src/main-clientSelection.html?'
			else
				page = 'src/main.html?'

		nw.Window.open page + $.param(params), {
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

		if typeof text isnt 'string'
			console.error "Tried to call renderLineBreaks on a non-string:", text
			return text


		lines = text.trim()
		.replace(/\r\n/g, '\n') # Windows -> Unix
		.replace(/\r/g, '\n') # old Mac -> Unix
		.split('\n')

		result = []

		for line, lineIndex in lines
			if lineIndex > 0
				result.push R.br({key: lineIndex})

			if line.trim()
				result.push line

		return result

	# Useful for conditionally hiding React components
	showWhen = (condition) ->
		if condition
			return ''

		return 'hide'

	showWhen3d = (condition) ->
		if condition
			return ''
		return 'shrink'

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

	renderTimeSpan = (startTimestamp, endTimestamp) ->
		startMoment = makeMoment(startTimestamp)

		if not endTimestamp
			# No endMoment means it's a point-event
			return startMoment.format(Config.timestampFormat)

		# Must be a span-event
		endMoment = makeMoment(endTimestamp)

		isFromStartOfDay = startMoment.format('HH:mm') is '00:00'
		isToEndOfDay = endMoment.format('HH:mm') is '23:59'

		if isFromStartOfDay and isToEndOfDay
			# Special case to only use date for a full-day event
			isSameDay = startMoment.isSame endMoment, 'day'

			if isSameDay
				return startMoment.format(Config.dateFormat)
			else
				return "#{startMoment.format(Config.dateFormat)} to #{endMoment.format(Config.dateFormat)}"

		# Otherwise, use default timeSpan format
		return "#{startMoment.format(Config.timestampFormat)} to #{endMoment.format(Config.timestampFormat)}"

	# Smooth-scroll utility, customized from https://pawelgrzybek.com/page-scroll-in-vanilla-javascript/
	# Uses nw win for requestAnimationFrame, and can handle scrolling within a container
	# paddingOffset makes it scroll a bit less, for more space on top
	scrollToElement = (container, element, duration = 500, easing = 'linear', paddingOffset, cb) ->
		# paddingOffset is optional arg
		if not cb?
			cb = paddingOffset
			paddingOffset = 10

		# container and element must both be valid
		if not container or not element
			arg = if element then 'container' else element
			throw new Error "Missing arg in scrollToElement for #{arg}"
			return

		easings =
			linear: (t) ->
				t
			easeInQuad: (t) ->
				t * t
			easeOutQuad: (t) ->
				t * (2 - t)
			easeInOutQuad: (t) ->
				if t < 0.5 then 2 * t * t else -1 + (4 - (2 * t)) * t
			easeInCubic: (t) ->
				t * t * t
			easeOutCubic: (t) ->
				--t * t * t + 1
			easeInOutCubic: (t) ->
				if t < 0.5 then 4 * t * t * t else (t - 1) * (2 * t - 2) * (2 * t - 2) + 1
			easeInQuart: (t) ->
				t * t * t * t
			easeOutQuart: (t) ->
				1 - (--t * t * t * t)
			easeInOutQuart: (t) ->
				if t < 0.5 then 8 * t * t * t * t else 1 - (8 * --t * t * t * t)
			easeInQuint: (t) ->
				t * t * t * t * t
			easeOutQuint: (t) ->
				1 + --t * t * t * t * t
			easeInOutQuint: (t) ->
				if t < 0.5 then 16 * t * t * t * t * t else 1 + 16 * --t * t * t * t * t

		start = container.scrollTop
		startTime = Date.now()

		# Figure out offset from top, minus any offset for the container itself
		topOffset = element.offsetTop
		containerOffset = $(container).position().top

		destination = topOffset - containerOffset

		# requestAnimationFrame can inf-loop if we dont set a limit
		maxScrollTop = container.scrollHeight - container.offsetTop

		# Can't scroll past maximum, otherwise apply paddingOffset
		if destination > maxScrollTop
			destination = maxScrollTop
		else
			destination -= paddingOffset

		# Can't scroll above top
		if destination < 0
			destination = 0

		# Cancel scroll if we're already at our destination
		if start is destination
			console.warn "Cancelled scroll (container.scrollTop is already #{start}px)"
			cb()
			return

		# Extra timeout safeguard against inf-loop after duration completes
		cancelOp = null
		console.log "scrollTop: #{start} -> #{destination}"

		setTimeout (-> cancelOp = true), duration + 10

		# Start the scroll loop
		scroll = ->
			now = Date.now()
			time = Math.min(1, (now - startTime) / duration)
			timeFunction = easings[easing](time)
			container.scrollTop = (timeFunction * (destination - start)) + start

			if container.scrollTop is destination or cancelOp
				console.log "Finished scrolling!"
				cb()
				return

			win.requestAnimationFrame scroll
			return

		scroll()
		return


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
		blockedExtensions
		CustomError
		executeIfFunction
		FaIcon
		openWindow
		renderLineBreaks
		renderName
		renderRecordId
		showWhen
		showWhen3d
		stripMetadata
		formatTimestamp
		capitalize
		truncateText
		makeMoment
		renderTimeSpan
		scrollToElement
		getUnitIndex
		getPlanSectionIndex
		getPlanTargetIndex
	}

module.exports = {
	load
	CustomError # for modules that can't provide a window object
}
