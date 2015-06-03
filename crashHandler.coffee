# This module handles unexpected errors caused by bugs in the application.
#
# Error info can be retrieved after the fact by running this in the console on
# the user's computer:
#  JSON.parse(localStorage.crashLog)

Moment = require 'moment'

{generateId} = require './persist'

load = (win) ->
	React = win.React
	R = React.DOM

	Gui = win.require 'nw.gui'
	nwWin = Gui.Window.get(win)

	handle = (err) ->
		# Record where this function was actually called from.
		# Sometimes this additional info is useful, because async calls often
		# obscure what caused an error.
		handlerStackTrace = new Error('handler call stack tracer').stack

		# React freaks out if you call React.render inside a component's render
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
				if crashLog.length > 1000
					crashLog = crashLog.slice(-1000)
				win.localStorage.crashLog = JSON.stringify(crashLog)

				# Show crash screen to user
				containerDiv = win.document.createElement 'div'
				win.document.body.appendChild containerDiv
				React.render CrashOverlay({crash}), containerDiv
			catch err2
				try
					console.error "CrashHandler has crashed."
					console.error err2
				catch err3
					# Nothing we can do...

	CrashOverlay = React.createFactory React.createClass
		render: ->
			return R.div({className: 'crashOverlay'},
				R.div({className: 'crashMessage'},
					R.h1({}, "Oops, something went wrong.")
					R.div({}, """
						KoNote encountered an unexpected error.
						If this happens repeatedly, please contact KoNode support
						and provide the following information:
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
						},
							"Close"
						)
					)
				)
			)
		_selectDebugInfo: ->
			React.findDOMNode(@refs.debugInfo).select()
		_close: ->
			nwWin.close true

	return {handle}

module.exports = {load}
