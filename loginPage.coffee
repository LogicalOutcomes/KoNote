Async = require 'async'
Imm = require 'immutable'

Config = require './config'
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
		mixins: [React.addons.PureRenderMixin]
		getInitialState: ->
			return {
				showForm: false
				userName: ''
				password: ''
				isLoading: true
			}
		componentDidMount: ->
			@_checkSetUp()

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
							@setState {showForm: true}
							@refs.userNameField.getDOMNode().focus()
							return

						# Data directory hasn't been set up yet.
						cb()
				(cb) =>
					Bootbox.confirm """
						KoNote could not find any data.  Unless this is your first
						time using KoNote, this may indicate a problem.  Would you
						like to set up KoNote from scratch?
					""", (result) =>
						unless result
							process.exit(0)
							return

						cb()
				(cb) =>
					Bootbox.prompt {
						title: 'Enter password for admin account'
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
								Bootbox.alert "An admin user account already exists."
								process.exit(1)
								return

							cb err
							return

						cb()
			], (err) =>
				if err
					CrashHandler.handle err
					return

				@setState {
					showForm: true
					userName: 'admin'
				}

				@refs.passwordField.getDOMNode().focus()

		render: ->
			return R.div({className: 'loginPage'},
				Spinner({
					isVisible: @state.isLoading
					isOverlay: true
				})
				R.form({className: "loginForm #{showWhen @state.showForm}"},
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
		_updateUserName: (event) ->
			@setState {userName: event.target.value}
		_updatePassword: (event) ->
			@setState {password: event.target.value}
		_login: (event) ->
			# TODO where to get data dir path? config?
			event.preventDefault()
			@setState {isLoading: true}

			Persist.Session.login 'data', @state.userName, @state.password, (err, session) =>
				@setState {isLoading: false}
				if err
					if err instanceof Persist.Session.UnknownUserNameError
						Bootbox.alert "Unknown user name.  Please try again."
						return

					if err instanceof Persist.Session.IncorrectPasswordError
						Bootbox.alert "Incorrect password.  Please try again.", =>
							@setState {password: ''}
						return

					CrashHandler.handle err
					return

				# Store this session for later use
				global.ActiveSession = session

				# Proceed to clientSelectionPage
				# TODO this should be abstracted similar to openWindow (see utils)
				win.location.href = 'main.html?page=clientSelection'	

module.exports = {load}
