# Load in Timeout listeners and trigger warning dialogs

load = (win) ->
	$ = win.jQuery
	React = win.React
	R = React.DOM
	Gui = win.require 'nw.gui'
	nwWin = Gui.Window.get(win)
	Config = require('./config')

	Dialog = require('./dialog').load(win)
	Spinner = require('./spinner').load(win)
	Persist = require './persist'
	Moment = require('moment')
	Bootbox = require('bootbox')

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
			@setState => isOpen: false
			clearInterval @counter

		showTimeoutMessage: ->
			@setState => isTimedOut: true

		_confirmPassword: ->
			@setState => isLoading: true

			Persist.Session.login 'data', global.ActiveSession.userName, @state.password, (err, result) =>
				@setState => isLoading: false

				if result
					global.ActiveSession.persist.eventBus.trigger 'timeout:reset'
				else
					if err instanceof Persist.Session.IncorrectPasswordError
						win.alert "Incorrect password"

		_updatePassword: (event) ->
			@setState {password: event.target.value}

		render: ->
			unless @state.isOpen
				return R.div({})

			countMoment = Moment.utc(@state.countSeconds * 1000)

			if @state.countSeconds is 60
				global.ActiveSession.persist.eventBus.trigger 'timeout:minuteWarning'

			return Dialog({
				title: "Inactivity Warning"
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
							"Your session has timed out. Please confirm your password for username \"#{global.ActiveSession.userName}\"to reactivate all windows."
							R.div({className: 'form-group'},
								R.input({
									value: @state.password
									onChange: @_updatePassword
									placeholder: "Confirm password"
									type: 'password'
								})
								R.div({className: 'btn-toolbar'},
									R.button({
										className: 'btn btn-primary'
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

		return {
			'timeout:initialWarning': =>
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
						body: "#{Config.productName} will shut down in 1 minute due to inactivity. " +
							"Any unsaved work will be lost!"
					}					
					nwWin.requestAttention(3)

			'timeout:reset': =>
				$('body').bind "mousemove mousedown keypress scroll", ->
					global.ActiveSession.persist.eventBus.trigger 'timeout:reset'

				# Reset both timeout component and session
				timeoutComponent.reset()
				global.ActiveSession.resetTimeout()

				# Reset knowledge of warnings been delivered
				global.ActiveSession.initialWarningDelivered = null
				global.ActiveSession.minuteWarningDelivered = null
			
			'timeout:timedOut': =>
				$('body').unbind "mousemove mousedown keypress scroll"
				# Force-close all windows when timed out
				console.log "TIMEOUT: Timed out, closing window"
				# nwWin.close(true)
				timeoutComponent.showTimeoutMessage()				

		}		

	return {getTimeoutListeners}

module.exports = {load}
