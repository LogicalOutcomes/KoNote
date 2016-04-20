# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

Config = require './config'
Persist = require './persist'
Atomic = require './persist/atomic'
Async = require 'async'
Fs = require 'fs'


load = (win) ->
	# Libraries from browser context
	$ = win.jQuery
	React = win.React
	R = React.DOM
	Bootbox = win.bootbox

	Gui = win.require 'nw.gui'
	Window = Gui.Window.get()

	Spinner = require('./spinner').load(win)
	CrashHandler = require('./crashHandler').load(win)
	{FaIcon} = require('./utils').load(win)



	NewInstallationPage = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		init: ->
			# First, we must test for write permissions
			@_testWritePermissions()

		deinit: (cb=(->)) ->
			cb()

		componentDidMount: ->
			Window.show()
			Window.focus()

		suggestClose: ->
			@refs.ui.suggestClose()

		_testWritePermissions: ->
			fileTestPath = './writeFileTest.txt'
			fileTestString = "Hello World!"			

			Async.series [
				(cb) => Fs.writeFile fileTestPath, fileTestString, cb
				(cb) => Fs.unlink fileTestPath, cb
			], (err) =>

				if err and err.code is 'EROFS'
					additionalMessage = unless process.platform is 'darwin' then "" else
						"Please make sure you have dragged #{Config.productName} into
						your Applications folder."

					Bootbox.alert """
						ERROR: '#{err.code}'.
						Unable to write to the local directory.
						#{additionalMessage}
					""", @props.closeWindow

					console.error "Unable to write to local directory:", err
					return

				else if err
					Bootbox.alert """
						ERROR: '#{err.code}'.
						Please contact #{Config.productName} technical support.
					""", @props.closeWindow

					console.error "Local directory write test error:", err
					return

				# Test successful
				console.log "Local directory is writeable!"


		render: ->
			return NewInstallationPageUi({
				ref: 'ui'
				closeWindow: @props.closeWindow
			})


	NewInstallationPageUi = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				openTab: 'index'

				isLoading: null
				installProgress: {
					message: null
					percent: null
				}

				password: ''
				passwordConfirmation: ''
			}

		componentDidUpdate: (oldProps, oldState) ->
			# Detech tab change to createAdmin
			if @state.openTab isnt oldState.openTab and @state.openTab is 'createAdmin'
				# Focus first password input
				$password = $(@refs.password)
				$password.focus()

		suggestClose: ->
			if global.isSetUp
				@props.closeWindow()
			else
				Bootbox.dialog {
					message: "Are you sure you want to cancel installation?"
					buttons: {
						cancel: {
							label: "No"
							className: 'btn-default'							
						}
						discard: {
							label: "Yes"
							className: 'btn-primary'
							callback: =>
								@props.closeWindow()
						}
					}
				}

		render: ->
			if @state.isLoading
				return R.div({id: 'newInstallationPage'},
					Spinner {
						isOverlay: true
						isVisible: true
						message: @state.installProgress.message
						percent: @state.installProgress.percent
					}
				)

			return R.div({
				id: 'newInstallationPage'
				className: 'animated fadeIn'
			},
				R.section({},
					R.div({
						id: 'brandContainer'
						className: 'animated fadeInDown'
					},
						R.div({},
							R.img({
								id: 'logoImage'
								src: './assets/brand/logo.png'
							})
							R.div({id: 'version'}, "v1.5.3 Beta")
						)						
					)
					R.div({
						id: 'contentContainer'
						# className: 'animated fadeInUp'
					},
						(switch @state.openTab
							when 'index'
								R.div({ref: 'index'},
									R.h2({}, "Thank you for trying the #{Config.productName} beta!")
									R.p({}, "To get started, let's set up your user account...")
									R.br({})
									R.div({className: 'btn-toolbar'},
										R.button({
											className: 'btn btn-lg btn-success'
											onClick: @_switchTab.bind null, 'createAdmin'
										}, 
											"Create Admin Account"
											FaIcon('arrow-right right-side')
										)
									)
								)
							when 'createAdmin'
								R.div({ref: 'createAdmin'},
									R.h2({}, "Your username will be \"admin\"")
									R.p({}, 								
										"Please choose a password"
									)
									R.div({
										id: 'passwordFields'
										className: 'row-fluid'
									},
										R.div({className: 'col-md-6'},
											R.div({
												className: [
													'form-group has-feedback'
													'has-success' if @state.password.length > 0
												].join ' '
											},
												R.label({
													htmlFor: 'password'
												}, "Password")
												R.input({
													ref: 'password'
													id: 'password'
													className: 'form-control'
													type: 'password'											
													placeholder: "Set Password"
													value: @state.password
													onChange: @_updatePassword											
												})
												R.span({className: 'glyphicon glyphicon-ok form-control-feedback'})
											)
										)
										R.div({className: 'col-md-6'},
											R.div({
												className: [
													'form-group has-feedback'
													if @_passwordsMatch()
														'has-success'
													else if @state.passwordConfirmation.length > 0
														'has-error'
												].join ' '
											},
												R.label({
													htmlFor: 'passwordConfirmation'
												}, "Confirm password")
												R.input({
													ref: 'passwordConfirmation'
													id: 'passwordConfirmation'
													className: 'form-control'
													type: 'password'											
													placeholder: "Password again"
													value: @state.passwordConfirmation
													onChange: @_updatePasswordConfirmation
												})
												R.span({className: 'glyphicon glyphicon-ok form-control-feedback'})
											)
										)
									)
									R.div({className: 'btn-toolbar'},
										R.button({
											className: [
												'btn btn-lg btn-success'
												'animated pulse' if @_passwordsMatch()
											].join ' '
											disabled: not @_passwordsMatch()
											onClick: @_install
										},
											"Create Account"
											FaIcon('check') if @_passwordsMatch()
										)
									)
								)

						)
					)
					R.div({
						id: 'helpContainer'
						className: 'animated fadeIn'
					}, 
						"Contact us:"						
						R.a({
							href: "#"
							onClick: @_copyHelpEmail.bind null, Config.supportEmailAddress
						},
							Config.supportEmailAddress
						)
					)
				)
			)

		_copyHelpEmail: (emailAddress) ->
			clipboard = Gui.Clipboard.get()
			clipboard.set emailAddress

			Bootbox.alert {
				title: "Copied Support E-mail"
				message: "\"#{emailAddress}\" copied to your clipboard!"
			}

		_updatePassword: (event) ->
			@setState {password: event.target.value}

		_updatePasswordConfirmation: (event) ->
			@setState {passwordConfirmation: event.target.value}

		_passwordsMatch: ->
			return @state.password is @state.passwordConfirmation and @state.password.length > 0

		_switchTab: (newTab) ->
			# TODO: Make this some kind of flexible component/mixin
			openTab = @state.openTab
			isIndex = openTab is 'index'
			
			# Animation directions
			offDirection = if isIndex then 'Left' else 'Right'
			onDirection = if isIndex then 'Right' else 'Left'

			# Transition out oldTab
			$oldTab = $(@refs[openTab])
			$oldTab.attr 'class', ('animated fadeOut' + offDirection)

			# Wait (.75 of anim default) and transition in the newTab
			setTimeout(=>
				@setState {openTab: newTab}, =>
					$newTab = $(@refs[newTab])
					$newTab.attr 'class', ('animated fadeIn' + onDirection)
			, 500)

		_updateProgress: (percent, message) ->
			if not percent and not message
				percent = message = null

			console.log "About to update progress..."

			@setState {
				isLoading: true
				installProgress: {percent, message}
			}

		_install: ->
			if @state.password isnt @state.passwordConfirmation
				Bootbox.alert "Passwords do not match"
				return

			systemAccount = null
			adminPassword = @state.password

			destDataDirectoryPath = Config.dataDirectory
			tempDataDirectoryPath = './data_tmp'

			# TODO: Check for previous tempDir existence

			# Write data folder to temporary local directory, before moving to destination
			Atomic.writeDirectoryNormally destDataDirectoryPath, tempDataDirectoryPath, (err, atomicOp) =>

				# Handle IO Errors
				if err and err instanceof Persist.IOError					
					switch err.cause.code
						when 'EEXIST'
							# Bootbox.confirm {
							# 	title: "Overwrite Previous/Pending Installation?"
							# 	message: """
							# 		It appears that you have a previously failed #{Config.productName} installation
							# 		attempt, or someone else is currently being installed by somebody else 
							# 		(less likely). Would you like to overrule this with a new installation?
							# 	"""
							# 	callback: (success) =>
							# 		if success
							# 			Fs.unlink 
							# }
							return
						else
							Bootbox.alert "IO Error"
							console.error "Error:", err
							return

				# Handle other [unknown] kinds of errors more critically
				else if err
					errCode = [
						err.name or ''
						err.code or err.cause.code
					].join ' '

					Bootbox.alert {
						title: "Error (#{errCode})"
						message: """
							Sorry, we seem to be having some trouble installing #{Config.productName}.
							Please check your network connection and try again, otherwise contact
							technical support at <u>#{Config.supportEmailAddress}</u> 
							with the Error Code: \"#{errCode}\" .
						"""
					}
					return

				Async.series [
					(cb) =>
						@_updateProgress 0, "Setting up database..."

						# Build the data directory, with subfolders/collections indicated in dataModels
						Persist.buildDataDirectory tempDataDirectoryPath, (err) =>
							if err
								cb err
								return

							cb()
					(cb) =>					
						@_updateProgress 25, "Generating secure encryption keys (this may take a while...)"
											
						isDone = false
						# Only fires if async setUp
						setTimeout(=>
							unless isDone
								@_updateProgress 50, "Setting up user account system (this may take a while...)"
						, 3000)

						# Generate mock "_system" admin user
						Persist.Users.Account.setUp tempDataDirectoryPath, (err, result) =>
							if err
								cb err
								return

							systemAccount = result
							isDone = true
							cb()
					(cb) =>
						@_updateProgress 75, "Creating your \"admin\" user . . ."
						# Create admin user account using systemAccount
						Persist.Users.Account.create systemAccount, 'admin', adminPassword, 'admin', (err) =>
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
						# Handle all types of errors

					console.log "Finished building local temp copy of dataDirectory"

					atomicOp.commit (err) =>
						if err
							CrashHandler.handle err
							# Handle commit errors

						console.log "Successfully installed #{Config.productName}!"
						@_updateProgress 100, "Successfully installed #{Config.productName}!"

						# Allow 1s for success animation before closing
						setTimeout(=>
							global.isSetUp = true
							win.close(true)
						, 1000)



	return NewInstallationPage

module.exports = {load}