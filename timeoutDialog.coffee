# Load in Timeout listeners and trigger warning dialogs

load = (win) ->
	$ = win.jQuery
	React = win.React
	R = React.DOM
	Gui = win.require 'nw.gui'
	nwWin = Gui.Window.get(win)
	Config = require('./config')

	Dialog = require('./dialog').load(win)
	Moment = require('moment')
	Bootbox = require('bootbox')

	TimeoutWarning = React.createFactory React.createClass
		getInitialState: ->
			return {
				countSeconds: null
				expiration: null
				isOpen: false
			}

		_recalculateSeconds: ->
			@setState => countSeconds: Moment(@state.expiration).diff(Moment(), 'seconds')

		show: ->
			@setState =>
				isOpen: true
				expiration: Moment().add(global.ActiveSession.warningMins, 'minutes')

			@_recalculateSeconds()

			@counter = setInterval(=> 
				@_recalculateSeconds()
			, 1000)

		reset: ->
			@setState => isOpen: false
			clearInterval @counter

		render: ->
			unless @state.isOpen
				return R.div({})

			countMoment = Moment.utc(@state.countSeconds * 1000)

			if @state.countSeconds is 60
				global.ActiveSession.persist.eventBus.trigger 'timeout:minuteWarning'

			return Dialog({
				title: "Inactivity Warning"
				containerClasses: [if @state.countSeconds <= 60 then 'warning']
			},
				R.div({className: 'timeoutDialog'},
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

	getTimeoutListeners = ->		
		# Fires 'resetTimeout' event upon any user interaction (move, click, typing, scroll)
		$('body').bind "mousemove mousedown keypress scroll", ->
			global.ActiveSession.persist.eventBus.trigger 'timeout:reset'	

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
						in #{Config.timeout.warningMins} minute#{if Config.timeout.warningMins > 1 then 's' else ''}"
					}					
					nwWin.requestAttention(1)

			'timeout:minuteWarning': =>
				unless global.ActiveSession.minuteWarningDelivered
					console.log "TIMEOUT: 1 Minute Warning issued"

					global.ActiveSession.minuteWarningDelivered = new win.Notification "1 Minute Warning!", {
						body: "#{Config.productName} will shut down in 1 minute due to inactivity. Any unsaved work will be lost!"
					}					
					nwWin.requestAttention(3)

			'timeout:reset': =>
				timeoutComponent.reset()

				# Reset knowledge of warnings been delivered
				global.ActiveSession.initialWarningDelivered = null
				global.ActiveSession.minuteWarningDelivered = null
			
			'timeout:timedOut': =>
				# Force-close all windows when timed out
				console.log "TIMEOUT: Timed out, closing window"
				nwWin.close(true)
		}		

	return {getTimeoutListeners}

module.exports = {load}
