# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Load in Timeout listeners and trigger warning dialogs

load = (win) ->
	$ = win.jQuery
	React = win.React
	R = React.DOM
	Bootbox = win.bootbox
	Gui = win.require 'nw.gui'
	nwWin = Gui.Window.get(win)
	Config = require('./config')

	Dialog = require('./dialog').load(win)
	Spinner = require('./spinner').load(win)
	Persist = require('./persist')	
	Moment = require('moment')	

	TimeoutWarning = React.createFactory React.createClass
		getInitialState: ->
			return {
				countSeconds: null
				expiration: null
				isOpen: false
				isTimedOut: false
				password: null
				isLoading: false
			}

		_recalculateSeconds: ->
			@setState => countSeconds: Moment(@state.expiration).diff(Moment(), 'seconds')

		show: ->
			@setState =>
				password: null
				isOpen: true
				expiration: Moment().add(global.ActiveSession.warningMins, 'minutes')

			@_recalculateSeconds()

			@counter = setInterval(=> 
				@_recalculateSeconds()
			, 1000)

		reset: ->
			@setState => 
				isOpen: false
				isTimedOut: false

			clearInterval @counter

		_focusPasswordField: ->
			setTimeout(=>
				@refs.passwordField.getDOMNode().focus()
			, 50)

		showTimeoutMessage: ->
			@setState => 
				isTimedOut: true
				password: null	
			@_focusPasswordField()		

		_confirmPassword: (event) ->
			event.preventDefault()

			@setState => isLoading: true

			global.ActiveSession.confirmPassword @state.password, (err, result) =>
				@setState => isLoading: false

				if err
					if err instanceof Persist.Session.DeactivatedAccountError
						Bootbox.alert "This user account has been deactivated."
						return

					if err instanceof Persist.Session.IncorrectPasswordError
						Bootbox.alert "Incorrect password for user \'#{global.ActiveSession.userName}\', please try again.", =>
							@setState => password: null
							@_focusPasswordField()
						return

					if err instanceof Persist.IOError
						Bootbox.alert "An error occurred. Please check your network connection and try again.", =>
							@_focusPasswordField()
						return

					CrashHandler.handle err
					return

				global.ActiveSession.persist.eventBus.trigger 'timeout:reactivateWindows'				

		_updatePassword: (event) ->			
			@setState {password: event.target.value}

		render: ->
			unless @state.isOpen
				return R.div({})

			countMoment = Moment.utc(@state.countSeconds * 1000)

			if @state.countSeconds is 60
				global.ActiveSession.persist.eventBus.trigger 'timeout:minuteWarning'

			return Dialog({
				title: if @state.isTimedOut then "Your Session Has Timed Out" else "Inactivity Warning"
				disableBackgroundClick: true
				containerClasses: [
					if @state.countSeconds <= 60 then 'warning'
					if @state.isTimedOut then 'timedOut'
				]				
			},
				R.div({className: 'timeoutDialog'},
					Spinner({
						isVisible: @state.isLoading
						isOverlay: true
					})
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

		timeoutComponent = React.render TimeoutWarning({}), timeoutContainer

		$('body').bind "mousemove mousedown keypress scroll", ->
			global.ActiveSession.persist.eventBus.trigger 'timeout:reset'

		return {
			'timeout:initialWarning': =>
				console.log "TIMEOUT: Initial Warning issued"

				timeoutComponent.show()

				unless global.ActiveSession.initialWarningDelivered
					console.log "TIMEOUT: Initial Warning issued"

					global.ActiveSession.initialWarningDelivered = new win.Notification "Inactivity Warning", {
						body: "Your #{Config.productName} session (and any unsaved work) will shut down 
						in #{Config.timeout.warningMins} 
						minute#{if Config.timeout.warningMins > 1 then 's' else ''}"
					}					
					nwWin.requestAttention(1)

			'timeout:minuteWarning': =>
				unless global.ActiveSession.minuteWarningDelivered
					console.log "TIMEOUT: 1 Minute Warning issued"

					global.ActiveSession.minuteWarningDelivered = new win.Notification "1 Minute Warning!", {
						body: "#{Config.productName} will disable all windows in 1 minute due to inactivity."
					}					
					nwWin.requestAttention(3)

			'timeout:reset': =>
				# Reset both timeout component and session
				timeoutComponent.reset()
				global.ActiveSession.resetTimeout()

				# Reset knowledge of warnings been delivered
				global.ActiveSession.initialWarningDelivered = null
				global.ActiveSession.minuteWarningDelivered = null

			'timeout:reactivateWindows': =>
				console.log "TIMEOUT: Confirmed password, reactivating windows"

				global.ActiveSession.persist.eventBus.trigger 'timeout:reset'

				$('body').bind "mousemove mousedown keypress scroll", ->
					global.ActiveSession.persist.eventBus.trigger 'timeout:reset'
			
			'timeout:timedOut': =>
				console.log "TIMEOUT: Timed out, disabling windows"

				$('body').unbind "mousemove mousedown keypress scroll"

				timeoutComponent.showTimeoutMessage()				

		}		

	return {getTimeoutListeners}

module.exports = {load}
