# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

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
	Gui = win.require 'nw.gui'
	Window = Gui.Window.get()

	NewInstallationPage = require('./newInstallationPage').load(win)

	CrashHandler = require('./crashHandler').load(win)
	Spinner = require('./spinner').load(win)
	Dialog = require('./dialog').load(win)
	{FaIcon, openWindow, renderName, showWhen} = require('./utils').load(win)

	LoginPage = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				isSetUp: null
				isNewSetUp: null

				isLoading: false

				newInstallationWindow: null
			}

		init: ->
			@_checkSetUp()

		deinit: (cb=(->)) ->
			@setState {isLoading: false}, cb

		suggestClose: ->
			@props.closeWindow()

		_activateWindow: ->
			@setState {isSetUp: true}			
			Window.show()
			Window.focus()

		render: ->
			unless @state.isSetUp
				return R.div({})

			LoginPageUi({
				ref: 'ui'

				isLoading: @state.isLoading
				loadingMessage: @state.loadingMessage

				isSetUp: @state.isSetUp
				isNewSetUp: @state.isNewSetUp
				activateWindow: @_activateWindow
				login: @_login
			})

		_checkSetUp: ->
			console.log "Probing setup..."

			# Check to make sure the dataDir exists and has an account system
			Persist.Users.isAccountSystemSetUp Config.dataDirectory, (err, isSetUp) =>
				@setState {isLoading: false}

				if err
					CrashHandler.handle err
					return

				if isSetUp					
					# Already set up, no need to continue here
					console.log "Set up confirmed..."
					@setState {isSetUp: true}
					return

				# Falsy isSetUp triggers NewInstallationPage
				console.log "Not set up, redirecting to installation page..."				
				@setState {isSetUp: false}

				@setState {
					newInstallationWindow: openWindow {
						page: 'newInstallation'
					}
				}, =>
					@state.newInstallationWindow.on 'close', (event) =>
						if global.isSetUp
							# Successfully installed, show login with isNewSetUp
							@setState {
								isSetUp: true
								isNewSetUp: true
							}
						else

							# Didn't complete installation, so close
							win.close(true)


		_login: (userName, password) ->
			# Run regex check on username first
			unless Persist.Users.userNameRegex.exec userName
				@refs.ui.onLoginError('InvalidUserNameError')
				return

			# Start authentication process
			@setState ->
				isLoading: true
				loadingMessage: "Authenticating..."

			Persist.Session.login Config.dataDirectory, userName, password, (err, session) =>				
				if err
					@setState
						isLoading: false
						loadingMessage: ""

					if err instanceof Persist.Session.UnknownUserNameError
						@refs.ui.onLoginError('UnknownUserNameError')
						return

					if err instanceof Persist.Session.IncorrectPasswordError
						@refs.ui.onLoginError('IncorrectPasswordError')
						return

					if err instanceof Persist.Session.DeactivatedAccountError
						@refs.ui.onLoginError('DeactivatedAccountError')
						return

					CrashHandler.handle err
					return

				@setState ->
					loadingMessage: "Logging in..."

				# Store the new session
				global.ActiveSession = session

				# Proceed to clientSelectionPage
				clientSelectionPageWindow = openWindow {
					page: 'clientSelection'
				}

				# Close loginPage once logged in
				clientSelectionPageWindow.on 'loaded', =>
					@setState 
						isLoading: false
						loadingMessage: ""

					Window.hide()

				clientSelectionPageWindow.on 'closed', =>
					@props.closeWindow()


	LoginPageUi = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]
		getInitialState: ->
			return {
				userName: ''
				password: ''
			}

		componentDidMount: ->
			@props.activateWindow()

			if @props.isNewSetUp
				@setState {userName: 'admin'}
				setTimeout(=>
					@refs.passwordField.focus()
				, 100)
			else
				setTimeout(=>
					@refs.userNameField.focus()
				, 100)

		onLoginError: (type) ->
			switch type
				when 'UnknownUserNameError'
					Bootbox.alert "Unknown user name. Please try again.", =>
						setTimeout(=>
							@refs.userNameField.focus()
						, 100)
				when 'IncorrectPasswordError'
					Bootbox.alert "Incorrect password. Please try again.", =>
						@setState {password: ''}
						setTimeout(=>
							@refs.passwordField.focus()
						, 100)
				when 'DeactivatedAccountError'
					Bootbox.alert "This user account has been deactivated.", =>
						@refs.userNameField.focus()
						setTimeout(=>
							@refs.userNameField.focus()
						, 100)
				when 'InvalidUserNameError'
					Bootbox.alert "Invalid user name. Please try again.", =>
						@refs.userNameField.focus()
						setTimeout(=>
							@refs.userNameField.focus()
						, 100)
				else
					throw new Error "Invalid Login Error"

		render: ->
			return R.div({className: 'loginPage animated fadeIn'},
				Spinner({
					isVisible: @props.isLoading
					isOverlay: true
					message: @props.loadingMessage
				})
				R.div({className: 'header'},
					FaIcon('times', {
						id: 'quitIcon'
						onClick: @_quit					
					})
				)
				R.div({id: "loginForm"},
					R.div({
						id: 'logoContainer'
						className: 'animated fadeInDown'
					},
						R.img({
							className: 'animated rotateIn'
							src: './assets/brand/kn.png'
						})
					)
					R.div({
						id: 'formContainer'
						className: 'animated fadeInUp'
					},
						R.div({className: 'form-group'},
							R.input({
								className: 'form-control'
								ref: 'userNameField'
								onChange: @_updateUserName
								onKeyDown: @_onEnterKeyDown
								value: @state.userName
								type: 'text'
								placeholder: 'Username'
							})
						)
						R.div({className: 'form-group'},
							R.input({
								className: 'form-control'
								type: 'password'
								ref: 'passwordField'
								onChange: @_updatePassword
								onKeyDown: @_onEnterKeyDown
								value: @state.password
								placeholder: 'Password'
							})
						)
						R.div({className: 'btn-toolbar'},
							#TODO: password reminder
#							R.button({
#								className: 'btn btn-link'
#								onClick: @_forgotPassword
#							}, "Forgot Password?")
							R.button({
								className: [
									'btn'
									if @_formIsInvalid() then 'btn-primary' else 'btn-success animated pulse'
								].join ' '
								type: 'submit'
								disabled: @_formIsInvalid()
								onClick: @_login
							}, "Sign in")
						)
					)
				)
			)

		_quit: ->
			win.close(true)
		
		_updateUserName: (event) ->
			@setState {userName: event.target.value}

		_updatePassword: (event) ->
			@setState {password: event.target.value}

		_onEnterKeyDown: (event) ->
			@_login() if event.which is 13 and not @_formIsInvalid()				
		
		_formIsInvalid: ->
			not @state.userName or not @state.password

		_login: (event) ->
			@props.login(@state.userName, @state.password)		


	return LoginPage

module.exports = {load}
