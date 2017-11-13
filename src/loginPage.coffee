# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Window for user login -> account validation, with detection for setup/migrations

Async = require 'async'
Fs = require 'fs'
Path = require 'path'
Semver = require 'semver'

Config = require './config'
Persist = require './persist'


load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM
	Window = nw.Window.get(win)

	CrashHandler = require('./crashHandler').load(win)
	Spinner = require('./spinner').load(win)
	{openWindow} = require('./utils').load(win)


	LoginPage = React.createFactory React.createClass
		displayName: 'LoginPage'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				isSetUp: null
				isNewSetUp: null
				isLoading: false
			}

		init: ->
			@_checkSetUp()

		deinit: (cb=(->)) ->
			@setState {isLoading: false}, cb

		suggestClose: ->
			@props.closeWindow()

		render: ->
			unless @state.isSetUp
				return null

			LoginPageUi({
				ref: 'ui'
				isLoading: @state.isLoading
				loadingMessage: @state.loadingMessage
				isNewSetUp: @state.isNewSetUp
				checkVersionsMatch: @_checkVersionsMatch
				login: @_login
			})

		_checkSetUp: ->
			# Check to make sure the dataDir exists and has an account system
			Persist.Users.isAccountSystemSetUp Config.backend, (err, isSetUp) =>
				if err
					if err instanceof Persist.IOError
						Bootbox.alert """
							Sorry, we're unable to reach the database.
							Please check your network connection and try again.
						"""
						return

					CrashHandler.handle err
					return

				if isSetUp
					# Already set up, no need to continue here
					@setState {
						isSetUp: true
					}
					return

				# Falsy isSetUp triggers NewInstallationPage
				console.log "Not set up, redirecting to installation page..."
				@setState {isSetUp: false}

				nw.Window.open 'src/main.html?' + $.param(page:'newInstallation'), {
					focus: false
					show: false
					width: 400
					height: 500
					min_width: 400
					min_height: 500
					icon: "src/icon.png"
				}, (newInstallationWindow) =>

					# Hide loginPage while installing
					Window.hide()

					newInstallationWindow.on 'closed', (event) =>
						if global.isSetUp
							# Successfully installed, show login with isNewSetUp
							@setState {
								isSetUp: true
								isNewSetUp: true
							}, Window.show()
						else
							# Didn't complete installation, so close window and quit the app
							@props.closeWindow()
							Window.quit()

		_checkVersionsMatch: ->
			dataDir = Config.backend.dataDirectory
			appVersion = nw.App.manifest.version

			# Read DB's version file, compare against app version
			Fs.readFile Path.join(dataDir, 'version.json'), (err, result) =>
				if err
					if err instanceof Persist.IOError
						Bootbox.alert "Please check your network connection and try again."
						return

					CrashHandler.handle err
					return

				dbVersion = JSON.parse(result).dataVersion

				# Launch migration dialog if mismatched versions
				if Semver.lt(dbVersion, appVersion)
					console.log "data version less than app version. Migration required"
					@_showMigrationDialog(dbVersion, appVersion)
				else if Semver.gt(dbVersion, appVersion)
					console.log "Warning! Data version newer than app version"
					Bootbox.dialog {
						title: "Database Error"
						message: """
							The application cannot start because your database appears to be from a newer version of #{Config.productName}.<br><br>
							You must upgrade #{Config.productName} from v#{appVersion} to v#{dbVersion} or greater to continue.<br><br>
							If you believe you are seeing this message in error, please contact support at #{Config.supportEmailAddress}.
						"""
						closeButton: false
						buttons: {
							cancel: {
								label: "OK"
								className: 'btn-primary'
								callback: =>
									@props.closeWindow()
							}
						}
					}


		_showMigrationDialog: (dbVersion, appVersion) ->
			$ =>
				Bootbox.dialog {
					title: "Database Migration Required"
					message: """
						Your database is from an earlier version of #{Config.productName} (<strong>v#{dbVersion}</strong>), so a migration is required.<br><br>
						To update the database to <strong>v#{appVersion}</strong>, please log in with an administrator account:<br><br>
						<input id="username" name="username" type="text" placeholder="username" class="form-control input-md"><br>
						<input id="password" name="password" type="password" placeholder="password" class="form-control input-md"><br>
					"""
					closeButton: false
					buttons: {
						cancel: {
							label: "Cancel"
							className: 'btn-default'
							callback: =>
								@props.closeWindow()
						}
						continue: {
							label: "Continue"
							className: 'btn-primary'
							callback: =>
								# passing a string to the migrate function if the fields are left empty
								# this lets the existing error conditions handle empty fields.
								username = $('#username').val() or ' '
								password = $('#password').val() or ' '
								@_migrateToLatestVersion(username, password, dbVersion)
						}
					}
				}

				# Focus first field
				# bootbox focuses primary button by default
				setTimeout(->
					$('#username').focus()
				, 500)

		_migrateToLatestVersion: (username, password, currentVersion) ->
			Migration = require './migrations'
			dataDir = Config.backend.dataDirectory
			destinationVersion = nw.App.manifest.version

			Async.series [
				(cb) =>
					@setState {isLoading: true, loadingMessage: "Migrating Database..."}, cb

				(cb) =>
					Migration.atomicMigration dataDir, currentVersion, destinationVersion, username, password, cb

			], (err) =>
				@setState {isLoading: false, loadingMessage: ""}

				# ToDo: handle case where migration file is not found
				if err
					if err instanceof Persist.Session.AccountTypeError
						@refs.ui.onLoginError('AccountTypeError', @_checkVersionsMatch)
						return

					if err instanceof Persist.Session.UnknownUserNameError
						@refs.ui.onLoginError('UnknownUserNameError', @_checkVersionsMatch)
						return

					if err instanceof Persist.Session.InvalidUserNameError
						@refs.ui.onLoginError('InvalidUserNameError', @_checkVersionsMatch)
						return

					if err instanceof Persist.Session.IncorrectPasswordError
						@refs.ui.onLoginError('IncorrectPasswordError', @_checkVersionsMatch)
						return

					if err instanceof Persist.Session.DeactivatedAccountError
						@refs.ui.onLoginError('DeactivatedAccountError', @_checkVersionsMatch)
						return

					if err instanceof Persist.Session.IOError
						@refs.ui.onLoginError('IOError', @_checkVersionsMatch)
						return

					CrashHandler.handle err
					return

				# Migrations were successful!
				Bootbox.alert "The data file has been successfully migrated to the app version. Please log in to continue."

		_login: (userName, password) ->
			Async.series [
				(cb) =>
					@setState {isLoading: true, loadingMessage: "Authenticating..."}, cb

				(cb) =>
					# Create session
					Persist.Session.login userName, password, Config.backend, (err, session) =>
						if err
							cb err
							return

						# Store the session globally
						global.ActiveSession = session
						cb()

				(cb) =>
					openWindow {page: 'clientSelection'}, (newWindow) =>
						clientSelectionPageWindow = newWindow

						Window.hide()

						clientSelectionPageWindow.on 'closed', =>
							@props.closeWindow()
							Window.quit()

						# Finish series and hide loginPage once loaded event fires
						global.ActiveSession.persist.eventBus.once 'clientSelectionPage:loaded', cb

			], (err) =>
				@setState {isLoading: false, loadingMessage: ""}

				if err

					if err instanceof Persist.Session.UnknownUserNameError
						@refs.ui.onLoginError('UnknownUserNameError')
						return

					if err instanceof Persist.Session.InvalidUserNameError
						@refs.ui.onLoginError('InvalidUserNameError')
						return

					if err instanceof Persist.Session.IncorrectPasswordError
						@refs.ui.onLoginError('IncorrectPasswordError')
						return

					if err instanceof Persist.Session.DeactivatedAccountError
						@refs.ui.onLoginError('DeactivatedAccountError')
						return

					if err instanceof Persist.Session.IOError
						@refs.ui.onLoginError('IOError')
						return

					CrashHandler.handle err
					return


	LoginPageUi = React.createFactory React.createClass
		displayName: 'LoginPageUi'
		mixins: [React.addons.PureRenderMixin]
		getInitialState: ->
			return {
				userName: ''
				password: ''
			}

		componentWillMount: ->
			if @props.isNewSetUp
				@setState {userName: 'admin'}

		componentDidMount: ->
			@props.checkVersionsMatch()
			if @props.isNewSetUp
				@refs.passwordField.focus()

		onLoginError: (type, cb=(->)) ->
			switch type
				when 'AccountTypeError'
					Bootbox.alert "This user is not an Admin. Please try again.", =>
						setTimeout(=>
							@refs.userNameField.focus()
						, 100)
						cb()

				when 'UnknownUserNameError'
					Bootbox.alert "Unknown user name. Please try again.", =>
						setTimeout(=>
							@refs.userNameField.focus()
						, 100)
						cb()
				when 'InvalidUserNameError'
					Bootbox.alert "Invalid user name. Please try again.", =>
						@refs.userNameField.focus()
						setTimeout(=>
							@refs.userNameField.focus()
						, 100)
						cb()
				when 'IncorrectPasswordError'
					Bootbox.alert "Incorrect password. Please try again.", =>
						@setState {password: ''}
						setTimeout(=>
							@refs.passwordField.focus()
						, 100)
						cb()
				when 'DeactivatedAccountError'
					Bootbox.alert "This user account has been deactivated.", =>
						@refs.userNameField.focus()
						setTimeout(=>
							@refs.userNameField.focus()
						, 100)
						cb()
				when 'IOError'
					Bootbox.alert "Please check your network connection and try again.", cb
				else
					throw new Error "Invalid Login Error"

		render: ->
			return R.div({className: 'loginPage'},
				Spinner({
					isVisible: @props.isLoading
					isOverlay: true
					message: @props.loadingMessage
				})
				R.div({id: "loginForm"},
					R.div({
						id: 'logoContainer'
						className: 'animated fadeInDown'
					},
						R.img({
							className: 'animated rotateIn'
							src: 'img/konode-kn.svg'
						})
					)
					R.div({
						id: 'formContainer'
						className: 'animated fadeInUp'
					},
						R.div({className: 'form-group'},
							R.input({
								className: 'form-control'
								autoFocus: true
								ref: 'userNameField'
								onChange: @_updateUserName
								onKeyDown: @_onEnterKeyDown
								value: @state.userName
								type: 'text'
								placeholder: 'Username'
								autoComplete: 'off'
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
								autoComplete: 'off'
							})
						)
						R.div({className: 'btn-toolbar'},
							## TODO: Password reminder
							# R.button({
							# 	className: 'btn btn-link'
							# 	onClick: @_forgotPassword
							# }, "Forgot Password?")
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
			@props.login(@state.userName.split('@')[0], @state.password)


	return LoginPage


module.exports = {load}
