Imm = require 'immutable'

Config = require './config'
Persist = require './persist'

load = (win) ->
	# Libraries from browser context
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM
	Spinner = require('./spinner').load(win)
	{FaIcon, openWindow, renderName, showWhen} = require('./utils').load(win)

	do ->
		init = ->
			render()
			loadData()
			registerListeners()

		process.nextTick init

		render = ->
			React.render new LoginPage(), $('#container')[0]

		loadData = ->
			# TODO load teh datas?

		registerListeners = ->
			# TODO listen for a change?

	LoginPage = React.createFactory React.createClass
		getInitialState: ->
			return {
				userName: ''
				password: ''
			}
		componentDidMount: ->
			@refs.userNameField.getDOMNode().focus()
		render: ->
			return R.div({className: 'loginPage'},
				R.div({className: 'loginForm'},
					R.div({className: 'form-group'},
						R.label({}, "User name")
						R.input({
							className: 'form-control'
							ref: 'userNameField'
							onChange: @_updateUserName
							value: @state.userName
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "Password")
						R.input({
							className: 'form-control'
							type: 'password'
							ref: 'passwordField'
							onChange: @_updatePassword
							value: @state.password
						})
					)
					R.div({className: 'btn-toolbar'},
						R.button({
							className: 'btn btn-primary'
							onClick: @_login
						}, "Sign in")
					)
				)
			)
		_updateUserName: (event) ->
			@setState {userName: event.target.value}
		_updatePassword: (event) ->
			@setState {password: event.target.value}
		_login: (event) ->
			# TODO check if fields are blank
			# TODO show loading indicator
			# TODO where to get data dir path? config?
			Persist.Session.login 'data', @state.userName, @state.password, (err, session) =>
				if err
					if err instanceof Persist.Session.UnknownUserNameError
						Bootbox.alert "Unknown user name.  Please try again.", =>
							@refs.userNameField.getDOMNode().select()
						return

					if err instanceof Persist.Session.IncorrectPasswordError
						Bootbox.alert "Incorrect password.  Please try again.", =>
							pwField = @refs.passwordField.getDOMNode()
							pwField.value = ''
							pwField.focus()
						return

					console.error err.stack
					Bootbox.alert "An error occurred while logging in.  Please try again later."
					return

				Bootbox.alert "Success!"
				# TODO ...

module.exports = {load}
