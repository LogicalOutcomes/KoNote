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

	NewInstallationPage = require('./newInstallationPage').load(win)

	CrashHandler = require('./crashHandler').load(win)
	Spinner = require('./spinner').load(win)
	Dialog = require('./dialog').load(win)
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

		deinit: (cb=(->)) ->
			@setState {isLoading: false}, cb

		suggestClose: ->
			@props.closeWindow()

		componentWillMount: ->
			if Config.autoLogin?
				@_login Config.autoLogin.userName, Config.autoLogin.password
				return null

		render: ->
			return new LoginPageUi({
				ref: 'ui'
				isLoading: @state.isLoading
				isSetUp: @state.isSetUp
				login: @_login
			})

		_checkSetUp: ->
			adminPassword = null
			systemAccount = null

			Async.series [
				(cb) =>
					Persist.Users.isAccountSystemSetUp Config.dataDirectory, (err, isSetUp) =>
						@setState {isLoading: false}

						if err
							cb err
							return

						# if isSetUp
						# 	# Already set up, no need to continue here
						# 	@setState {isSetUp: true}, =>
						# 		@refs.ui.isSetUp()
						# 	return

						# Data directory hasn't been set up yet.
						cb()
				(cb) =>
					containerElem = $('#container')[0]

					React.render NewInstallationPage({
						onSuccess: (password) ->
							adminPassword = password
							cb()
					}), containerElem
				
			], (err) =>
				if err
					CrashHandler.handle err
					return

				@refs.ui.prepareForAdmin()
				@setState {isSetUp: true}

		_login: (userName, password) ->			
			@setState => isLoading: true

			Persist.Session.login Config.dataDirectory, userName, password, (err, session) =>
				@setState {isLoading: false}
				if err
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

				# Store this session for later use
				global.ActiveSession = session

				# Proceed to clientSelectionPage
				@props.navigateTo {
					page: 'clientSelection'
				}


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
			unless Config.autoLogin?
				setTimeout(=>
					@refs.userNameField.getDOMNode().focus()
				, 100)

		onLoginError: (type) ->
			switch type
				when 'UnknownUserNameError'
					Bootbox.alert "Unknown user name.  Please try again."
				when 'IncorrectPasswordError'
					Bootbox.alert "Incorrect password.  Please try again."
					@setState {password: ''}
				when 'DeactivatedAccountError'
					Bootbox.alert "This user account has been deactivated."
				else
					throw new Error "Invalid Login Error"

		render: ->
			if Config.autoLogin?
				return R.div({className: 'loginPage'},
					R.div({className: 'autoLogin'}, "Auto-Login Enabled . . .")
				)

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
							type: 'text'
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
