# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# This module handles unexpected errors caused by bugs in the application.
#
# Error info can be retrieved after the fact by running this in the console on
# the user's computer:
#  JSON.parse(localStorage.crashLog)

Moment = require 'moment'

{generateId} = require './persist'

load = (win) ->
	React = require 'react'
	ReactDOM = require 'react-dom'
	R = React.DOM
	PureRenderMixin = require 'react-addons-pure-render-mixin'

	nwWin = nw.Window.get(win)
	{FaIcon} = require('./utils').load(win)

	handle = (err) ->
		# Show NW window, in case it's still hidden
		# Exclude loginPage, since it's meant to be hidden
		if win.pageParameters and not win.pageParameters.page is 'login' and global.ActiveSession?
			nwWin.show()

		# Record where this function was actually called from.
		# Sometimes this additional info is useful, because async calls often
		# obscure what caused an error.
		handlerStackTrace = new Error('handler call stack tracer').stack

		# React freaks out if you call R.render inside a component's render
		# method.  nextTick works around this.
		process.nextTick ->
			try
				# Log to console first
				console.error "CrashHandler received an error:"
				console.error err
				console.error err.stack

				# Create crash report object
				crash = {
					id: generateId()
					platform: process.platform
					arch: process.arch
					userAgent: win.navigator.userAgent
					nwVersion: process.versions["node-webkit"]
					cwd: process.cwd()
					url: win.location.href
					timestamp: Moment().format()
					error: err.toString()
					errorStackTrace: err.stack
					errorHandlerStackTrace: handlerStackTrace
				}

				# Log to localStorage
				crashLog = JSON.parse(win.localStorage.crashLog or '[]')
				crashLog.push crash
				if crashLog.length > 100
					crashLog = crashLog.slice(-100)
				win.localStorage.crashLog = JSON.stringify(crashLog)

				# Show crash screen to user
				containerDiv = win.document.createElement 'div'
				win.document.body.appendChild containerDiv
				ReactDOM.render CrashOverlay({crash}), containerDiv
			catch err2
				try
					console.error "CrashHandler has crashed."
					console.error err2
				catch err3
					# Nothing we can do...

	CrashOverlay = React.createFactory React.createClass
		displayName: 'CrashOverlay'
		mixins: [PureRenderMixin]
		render: ->
			return R.div({className: 'crashOverlay'},
				R.div({className: 'crashMessage'},
					R.img({src: './assets/brand/kn.png'})
					R.h1({}, "Oops, something went wrong.")
					R.div({}, """
						KoNote encountered an unexpected error.
						If this happens repeatedly, please copy the error message below
						and send to KoNode support with details on how you encountered it.
						Thank you!
					""")
					R.textarea({
						className: 'debugInfo'
						ref: 'debugInfo'
						disabled: false
						value: JSON.stringify @props.crash
						onClick: @_selectDebugInfo
						onChange: (->) # do nothing
					})
					R.div({className: 'buttonContainer'},
						R.button({
							className: 'btn btn-default'
							onClick: @_close
						}, "Close")
						R.button({
							className: 'btn btn-default'
							onClick: @_copyCrashTrace
						},
							"Copy "
							FaIcon('copy')
						)
					)
				)
			)

		_copyCrashTrace: ->
			clipboard = nw.Clipboard.get()
			clipboard.set JSON.stringify @props.crash

		_selectDebugInfo: ->
			@refs.debugInfo.select()

		_close: ->
			nwWin.close true

	return {handle}

module.exports = {load}
