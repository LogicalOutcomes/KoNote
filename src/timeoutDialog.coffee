# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Load in Timeout listeners and trigger warning dialogs

Config = require './config'
Persist = require './persist'

load = (win) ->
	$ = win.jQuery
	React = win.React
	ReactDOM = win.ReactDOM
	R = React.DOM
	Bootbox = win.bootbox
	Gui = win.require 'nw.gui'
	nwWin = Gui.Window.get(win)

	Dialog = require('./dialog').load(win)
	Spinner = require('./spinner').load(win)
	CrashHandler = require('./crashHandler').load(win)

	Moment = require('moment')

	TimeoutDialog = React.createFactory React.createClass
		displayName: 'TimeoutDialog'

		getInitialState: ->
			return {
				countSeconds: null
				expiration: null
				isOpen: false
				isFinalWarning: false
				isTimedOut: false
				password: ''
			}

		_recalculateSeconds: ->
			@setState => countSeconds: Moment(@state.expiration).diff(Moment(), 'seconds')

		show: ->
			@setState =>
				password: ''
				isOpen: true
				expiration: Moment().add(Config.timeout.warnings.initial, 'minutes')

			@_recalculateSeconds()

			@counter = setInterval(=>
				@_recalculateSeconds()
			, 1000)

		showFinalWarning: ->
			@setState {isFinalWarning: true}

		reset: ->
			clearInterval @counter

			return unless @state.isOpen or @state.isFinalWarning or @state.isTimedOut

			@setState {
				isOpen: false
				isFinalWarning: false
				isTimedOut: false
			}

		_focusPasswordField: ->
			setTimeout(=>
				@refs.passwordField.focus()
			, 50)

		showTimeoutMessage: ->
			@setState =>
				isTimedOut: true
				password: ''
			@_focusPasswordField()

		_confirmPassword: (event) ->
			event.preventDefault()

			@refs.dialog.setIsLoading true

			global.ActiveSession.confirmPassword @state.password, (err, result) =>
				@refs.dialog.setIsLoading(false) if @refs.dialog?

				if err
					if err instanceof Persist.Session.IncorrectPasswordError
						Bootbox.alert "Incorrect password for user \'#{global.ActiveSession.userName}\', please try again.", =>
							@setState => password: ''
							@_focusPasswordField()
						return

					if err instanceof Persist.Session.DeactivatedAccountError
						Bootbox.alert "This user account has been deactivated."
						return

					if err instanceof Persist.IOError
						Bootbox.alert "An error occurred. Please check your network connection and try again.", =>
							@_focusPasswordField()
						return

					console.error "Timeout Login Error:", err

					CrashHandler.handle err
					return

				global.ActiveSession.persist.eventBus.trigger 'timeout:reactivateWindows'

		_updatePassword: (event) ->
			@setState {password: event.target.value}

		render: ->
			unless @state.isOpen
				return R.div({})

			countMoment = Moment.utc(@state.countSeconds * 1000)

			return Dialog({
				ref: 'dialog'
				title: if @state.isTimedOut then "Your Session Has Timed Out" else "Inactivity Warning"
				disableBackgroundClick: true
				containerClasses: [
					'timedOut' if @state.isTimedOut
					'warning' if @state.isFinalWarning
				]
			},
				R.div({className: 'timeoutDialog'},
					(if @state.isTimedOut
						R.div({className: 'message'},
							"Please confirm your password for user \"#{global.ActiveSession.userName}\"
							to restore all windows."
							R.form({className: 'form-group'},
								R.input({
									value: @state.password
									onChange: @_updatePassword
									placeholder: "● ● ● ● ●"
									type: 'password'
									ref: 'passwordField'
								})
								R.div({className: 'btn-toolbar'},
									R.button({
										className: 'btn btn-primary btn-lg btn-block'
										disabled: not @state.password
										type: 'submit'
										onClick: @_confirmPassword
									}, "Confirm Password")
								)
							)
						)
					else
						R.div({className: 'message'},
							"Your #{Config.productName} session will shut down in "
							R.span({className: 'timeRemaining'},
								if @state.countSeconds >= 60
									"#{countMoment.format('mm:ss')} minutes"
								else
									"#{countMoment.format('ss')} seconds"
							)
							"due to inactivity"
							R.br({})
							R.br({})
							"Any unsaved work will be lost!"
						)
					)
				)
			)

	getTimeoutListeners = ->
		# Fires 'resetTimeout' event upon any user interaction (move, click, typing, scroll)

		timeoutContainer = win.document.createElement('div')
		timeoutContainer.id = 'timeoutContainer'
		win.document.body.appendChild timeoutContainer

		timeoutComponent = ReactDOM.render TimeoutDialog({}), timeoutContainer

		$('body').bind "mousemove mousedown keypress scroll", ->
			global.ActiveSession.persist.eventBus.trigger 'timeout:reset'

		return {
			'timeout:initialWarning': =>
				timeoutComponent.show()

				unless global.ActiveSession.initialWarningDelivered
					console.log "TIMEOUT: Initial Warning issued"

					global.ActiveSession.initialWarningDelivered = new win.Notification "Inactivity Warning", {
						body: "Your session will expire in #{Config.timeout.warnings.initial}
						minute#{if Config.timeout.warnings.initial > 1 then 's' else ''}"
					}
					nwWin.requestAttention(1)

			'timeout:finalWarning': =>
				timeoutComponent.showFinalWarning()

				unless global.ActiveSession.finalWarningDelivered
					console.log "TIMEOUT: Final Warning issued"

					global.ActiveSession.finalWarningDelivered = new win.Notification "Final Warning", {
						body: "#{Config.productName} will disable all windows in #{Config.timeout.warnings.final}
						minute#{if Config.timeout.warnings.final > 1 then 's' else ''} due to inactivity."
					}
					nwWin.requestAttention(1)

			'timeout:reset': =>
				# Reset both timeout component and session
				timeoutComponent.reset()
				global.ActiveSession.resetTimeout()

				# Reset knowledge of warnings been delivered
				global.ActiveSession.initialWarningDelivered = null
				global.ActiveSession.finalWarningDelivered = null

			'timeout:reactivateWindows': =>
				console.log "TIMEOUT: Confirmed password, reactivating windows"

				global.ActiveSession.persist.eventBus.trigger 'timeout:reset'

				$('body').bind "mousemove mousedown keypress scroll", (event) ->
					global.ActiveSession.persist.eventBus.trigger 'timeout:reset'

			'timeout:timedOut': =>
				console.log "TIMEOUT: Timed out, disabling windows"

				$('body').unbind "mousemove mousedown keypress scroll"

				timeoutComponent.showTimeoutMessage()

		}

	return {getTimeoutListeners}

module.exports = {load}
