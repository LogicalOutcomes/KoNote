# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

Config = require './config'
Persist = require './persist'
Async = require 'async'

load = (win) ->
	# Libraries from browser context
	$ = win.jQuery
	React = win.React
	R = React.DOM
	Bootbox = win.bootbox

	Gui = win.require 'nw.gui'
	Window = Gui.Window.get()

	Spinner = require('./spinner').load(win)	
	{FaIcon} = require('./utils').load(win)

	NewInstallationPage = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		init: -> # Nothing yet

		deinit: (cb=(->)) ->
			cb()

		componentDidMount: ->
			Window.focus()

		suggestClose: ->
			@refs.ui.suggestClose()

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
							R.div({id: 'version'}, "v1.4.0 Beta")
						)						
					)
					R.div({
						id: 'contentContainer'
						className: 'animated fadeInUp'
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
										"Please choose a password:"
										R.br({})
										R.br({})
									)
									R.div({
										className: [
											'form-group'
											'has-success has-feedback' if @state.password.length > 0
										].join ' '
									},
										R.input({
											ref: 'password'
											className: 'form-control'
											type: 'password'											
											placeholder: "Set Password"
											value: @state.password
											onChange: @_updatePassword											
										})
										R.span({className: 'glyphicon glyphicon-ok form-control-feedback'})
									)
									R.div({
										className: [
											'form-group'
											if @_passwordsMatch()
												'has-success has-feedback'
											else if @state.passwordConfirmation.length > 0
												'has-error'
										].join ' '
									},
										R.input({
											ref: 'passwordConfirmation'
											className: 'form-control'
											type: 'password'											
											placeholder: "Confirm Password"
											value: @state.passwordConfirmation
											onChange: @_updatePasswordConfirmation
										})
										R.span({className: 'glyphicon glyphicon-ok form-control-feedback'})
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
						R.a({href: 'mailto:help@konode.ca'},
							"help@konode.ca"
						)
					)
				)
			)

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

		_showContactInfo: ->
			Bootbox.dialog {
				title: "Contact Information:"
				message: """
					<ul>
						<li>E-mail: david@konode.ca</li>
						<li>Phone: 1-416-816-3422</li>
					</ul>
				"""
				buttons: {
					success: {
						label: "Done"
						className: 'btn btn-success'
					}
				}
			}

		_updateProgress: (percent, message) ->
			if not percent and not message
				percent = message = null

			console.log "About to update progress..."

			@setState {
				isLoading: true
				installProgress: {percent, message}
			}, ->
				console.log "Updated progress:", percent, message

		_install: ->
			if @state.password isnt @state.passwordConfirmation
				Bootbox.alert "Passwords do not match"
				return

			systemAccount = null
			adminPassword = @state.password

			Async.series [
				(cb) =>
					@_updateProgress 0, "Setting up database..."

					# Set up data directory, with subfolders from dataModels
					Persist.setUpDataDirectory Config.dataDirectory, (err) =>
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
					Persist.Users.Account.setUp Config.dataDirectory, (err, result) =>
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
					return

				@_updateProgress 100, "Successfully installed #{Config.productName}!"

				setTimeout(=>
					global.isSetUp = true
					win.close(true)
				, 1000)



	return NewInstallationPage

module.exports = {load}