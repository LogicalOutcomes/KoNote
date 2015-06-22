# Load in Timeout listeners and trigger warning dialogs

# Must add TimeoutListeners() function to load/init/registerListeners
# on every page

load = (win) ->
	$ = win.jQuery
	React = win.React
	R = React.DOM
	Gui = win.require 'nw.gui'
	nwWin = Gui.Window.get(win)

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
				console.log "Reset Timeout"
				clearInterval @counter
				@setState {isOpen: false}

		_dismissWarning: ->			
			global.ActiveSession.persist.eventBus.trigger 'resetTimeout'

		render: ->
			unless this.state.isOpen
				return R.div({})

			return Dialog({
				title: "Inactivity Warning"
				onClose: @_dismissWarning
				ref: 'timeoutDialog'
			},
				R.div({className: 'timeoutDialog'},
					R.div({className: 'message'},
						"Your session will expire in "
						R.span({}, Moment(@state.count, 'seconds').format('mm:ss'))
						R.button({
							className: 'btn btn-success'
							onClick: @_dismissWarning
						}, "I'm still working")
					)
				)
			)

	TimeoutListeners = ->
		global.ActiveSession.persist.eventBus.on 'issueTimeoutWarning', ->
			# Create div container
			containerDiv = win.document.createElement('div')
			containerDiv.id = 'timeoutContainer'
			win.document.body.appendChild containerDiv
			React.render TimeoutWarning({}), containerDiv		

		global.ActiveSession.persist.eventBus.on 'timedOut', ->
			nwWin.close(true)

	return {TimeoutListeners}

module.exports = {load}
