# Load in Timeout listeners and trigger warning dialogs

# Must add timeoutListeners() function to load/init/registerListeners on every page

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

	isClosed = null


	TimeoutWarning = React.createFactory React.createClass
		getInitialState: ->
			@_expiration = Moment().add(global.ActiveSession.warningMins, 'minutes')
			return {
				isOpen: true
				countSeconds: null
			}

		componentDidMount: ->
			clearInterval(@counter)
			@_recalculateSeconds()

			@counter = setInterval(=> 
				@_recalculateSeconds()
			, 1000)

			global.ActiveSession.persist.eventBus.on 'resetTimeout', =>
				clearInterval @counter
				@setState {isOpen: false}

		_recalculateSeconds: ->
			@setState {countSeconds: Moment(@_expiration).diff(Moment(), 'seconds')}

		render: ->
			unless @state.isOpen
				return R.div({})

			countMoment = Moment.utc(@state.countSeconds * 1000)

			if @state.countSeconds is 60
				global.ActiveSession.persist.eventBus.trigger 'issueMinuteWarning'

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

	timeoutListeners = ->
		global.ActiveSession.persist.eventBus.on 'issueTimeoutWarning', ->
			unless isClosed
				# Create and render into div container
				# TODO: Shouldn't have to re-create this every time
				containerDiv = win.document.createElement('div')
				win.document.body.appendChild containerDiv
				React.render TimeoutWarning({}), containerDiv

				unless global.ActiveSession.firstWarningDelivered
					console.log ">> First Warning issued"					
					nwWin.requestAttention(1)
					global.ActiveSession.firstWarningDelivered = new win.Notification "Inactivity Warning", {
						body: "Your #{Config.productName} session (and any unsaved work) will shut down 
						in #{Config.timeout.warningMins} minute#{if Config.timeout.warningMins > 1 then 's'}"
					}

		global.ActiveSession.persist.eventBus.on 'issueMinuteWarning', ->
			unless isClosed or global.ActiveSession.minWarningDelivered				
				console.log ">> 1 Minute Warning issued"
				console.log nwWin
				nwWin.requestAttention(3)
				global.ActiveSession.minWarningDelivered = new win.Notification "1 Minute Warning!", {
					body: "#{Config.productName} will shut down in 1 minute due to inactivity. Any unsaved work will be lost!"
				}

		# Force-close all windows when timed out
		global.ActiveSession.persist.eventBus.on 'timedOut', ->
			unless isClosed
				console.log ">> Timed out, closing window"
				# TODO: Needs to re-lock all client files that were open
				# Maybe this should be a logout instead of a force-close?
				nwWin.close(true)

		# Fires 'resetTimeout' event upon any user interaction (move, click, typing, scroll)
		$('body').bind "mousemove mousedown keypress scroll", ->
			global.ActiveSession.persist.eventBus.trigger 'resetTimeout'

	unregisterTimeoutListeners = ->
		isClosed = true

	return {
		timeoutListeners
		unregisterTimeoutListeners
	}

module.exports = {load}
