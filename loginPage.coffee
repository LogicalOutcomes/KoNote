Async = require 'async'
Imm = require 'immutable'

Config = require './config'
Term = require './term'
Persist = require './persist'

load = (win) ->
	# Libraries from browser context
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	CrashHandler = require('./crashHandler').load(win)
	Spinner = require('./spinner').load(win)
	{FaIcon, openWindow, renderName, showWhen} = require('./utils').load(win)

	LoginPage = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				isLoading: true
				isSetUp: false
			}

		init: ->
			@_checkSetUp()

		deinit: -> # Do nothing

		suggestClose: ->
			@props.closeWindow()

		render: ->
			return new LoginPageUi({
				ref: 'ui'
				isLoading: @state.isLoading
				isSetUp: @state.isSetUp
				login: @_login
			})

		_checkSetUp: ->
			adminPassword = null

			Async.series [
				(cb) =>
					# TODO data dir
					Persist.Users.isAccountSystemSetUp 'data', (err, isSetUp) =>
						@setState {isLoading: false}

						if err
							cb err
							return

						if isSetUp
							# Already set up, no need to continue here
							@setState {isSetUp: true}, =>
								@refs.ui.isSetUp()
							return

						# Data directory hasn't been set up yet.
						cb()
				(cb) =>
					# TODO: Move to ui
					Bootbox.confirm """
						#{Config.productName} could not find any data.  Unless this is your first
						time using #{Config.productName}, this may indicate a problem.  Would you
						like to set up #{Config.productName} from scratch?
					""", (result) =>
						unless result
							process.exit(0)
							return

						cb()
				(cb) =>
					# TODO: Move to ui
					Bootbox.prompt {
						title: "Enter password for admin #{Term 'account'}"
						inputType: 'password'
						callback: (result) ->
							unless result
								process.exit(0)
								return

							adminPassword = result
							cb()
					}
				(cb) =>
					# TODO data dir
					@setState {isLoading: true}
					Persist.setUpDataDirectory 'data', (err) =>
						@setState {isLoading: false}

						if err
							cb err
							return

						cb()
				(cb) =>
					# TODO data dir
					@setState {isLoading: true}
					Persist.Users.createAccount 'data', 'admin', adminPassword, 'admin', (err) =>
						@setState {isLoading: false}

						if err
							if err instanceof Persist.Users.UserNameTakenError
								Bootbox.alert "An admin #{Term 'user account'} already exists."
								process.exit(1)
								return

							cb err
							return

						cb()
			], (err) =>
				if err
					CrashHandler.handle err
					return

				@refs.ui.prepareForAdmin()
				@setState {isSetUp: true}

		_login: (userName, password) ->
			# TODO where to get data dir path? config?			
			@setState {isLoading: true}

			Persist.Session.login 'data', userName, password, (err, session) =>
				@setState {isLoading: false}
				if err
					if err instanceof Persist.Session.UnknownUserNameError
						@refs.ui.onLoginError('UnknownUserNameError')
						return

					if err instanceof Persist.Session.IncorrectPasswordError
						@refs.ui.onLoginError('IncorrectPasswordError')
						return

					CrashHandler.handle err
					return

				# Store this session for later use
				global.ActiveSession = session

				# Proceed to clientSelectionPage
				# TODO this should be abstracted similar to openWindow (see utils)
				win.location.href = 'main.html?page=clientSelection'	

	LoginPageUi = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]
		getInitialState: ->
			return {
				userName: ''
				password: ''
			}

		prepareForAdmin: ->
			@setState {userName: 'admin'}
			@refs.passwordField.getDOMNode().focus()

		isSetUp: ->
			@refs.userNameField.getDOMNode().focus()

		onLoginError: (type) ->
			switch type
				when 'UnknownUserNameError'
					Bootbox.alert "Unknown user name.  Please try again."
				when 'IncorrectPasswordError'
					Bootbox.alert "Incorrect password.  Please try again."
					@setState {password: ''}
				else
					throw new Error "Invalid Login Error"

		render: ->
			return R.div({className: 'loginPage'},
				Spinner({
					isVisible: @props.isLoading
					isOverlay: true
				})
				R.form({className: "loginForm #{showWhen @props.isSetUp}"},
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
							type: 'submit'
							disabled: not @state.userName or not @state.password
							onClick: @_login
						}, "Sign in")
					)
				)
			)
		_login: (event) ->
			event.preventDefault()
			@props.login(@state.userName, @state.password)
		_updateUserName: (event) ->
			@setState {userName: event.target.value}
		_updatePassword: (event) ->
			@setState {password: event.target.value}

	return LoginPage

module.exports = {load}
