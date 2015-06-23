# Load in Timeout listeners and trigger warning dialogs

# Must add TimeoutListeners() function to load/init/registerListeners
# on every page

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
				isOpen: true
				count: global.ActiveSession.warningMins * 60
			}

		componentDidMount: ->
			clearInterval(@counter)
			@counter = setInterval(=> 
				@setState {count: @state.count - 1}
			, 1000)

			global.ActiveSession.persist.eventBus.on 'resetTimeout', =>
				clearInterval @counter
				@setState {isOpen: false}

		render: ->
			unless @state.isOpen
				return R.div({})

			countMoment = Moment.utc(@state.count * 1000)

			if @state.count is 60
				new win.Notification "1 Minute Warning!", {
					body: "#{Config.productName} will shut down in 1 minute due to inactivity"
				}

			return Dialog({
				title: "Inactivity Warning"
				containerClasses: [if @state.count <= 60 then 'warning']
			},
				R.div({className: 'timeoutDialog'},
					R.div({className: 'message'},
						"Your #{Config.productName} session will shut down in "
						R.span({className: 'timeRemaining'},
							if @state.count >= 60
								"#{countMoment.format('mm:ss')} minutes"
							else
								"#{countMoment.format('ss')} seconds"
						)
						" due to inactivity."
					)
				)
			)

	TimeoutListeners = ->
		global.ActiveSession.persist.eventBus.on 'issueTimeoutWarning', ->
			# Create and render into div container
			# TODO: Shouldn't have to re-create this every time
			containerDiv = win.document.createElement('div')
			win.document.body.appendChild containerDiv
			React.render TimeoutWarning({}), containerDiv		

			# Directs user's attention to app about to time out
			nwWin.requestAttention(3)
			new win.Notification "Inactivity Warning", {
				body: "Your #{Config.productName} session will shut down 
				in #{Config.timeout.warningMins} minute#{if Config.timeout.warningMins > 1 then 's'}"
			}

		# Force-close all windows when timed out
		global.ActiveSession.persist.eventBus.on 'timedOut', ->
			# TODO: Needs to re-lock all client files that were open
			# Maybe this should be a logout instead of a force-close?
			nwWin.close(true)

		# Fires 'resetTimeout' event upon any user interaction (move, click, typing, scroll)
		$('body').bind "mousemove click keypress scroll", ->
			global.ActiveSession.persist.eventBus.trigger 'resetTimeout'

	return {TimeoutListeners}

module.exports = {load}
