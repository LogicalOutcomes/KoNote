# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

Config = require './config'

load = (win) ->
	# Libraries from browser context
	$ = win.jQuery
	React = win.React
	R = React.DOM

	{FaIcon} = require('./utils').load(win)

	NewInstallationPage = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				openTab: 'index'

				isLoading: null
				loadingMessage: ""

				password: ''
				passwordConfirmation: ''
			}

		render: ->
			return R.div({id: 'newInstallationPage'},
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
							R.div({id: 'version'}, "v1.4.0 (Beta)")
						)						
					)
					R.div({
						className: 'contentContainer'
					},
						(switch @state.openTab
							when 'index'
								R.div({ref: 'index'},
									R.h1({}, "You're almost done!")
									R.p({}, "Welcome to the #{Config.productName} beta program.")
									R.p({}, "Let's set you up with an \"admin\" account, and launch your new database.")
									R.div({className: 'btn-toolbar'},
										R.button({
											className: 'btn btn-lg btn-default'
										}, 
											"Help"
										)
										R.button({
											className: 'btn btn-lg btn-primary'
											onClick: @_switchTab.bind null, 'createAdmin'
										}, 
											"Create Admin Account"
											FaIcon('arrow-right')
										)
									)
								)
							when 'createAdmin'
								R.div({ref: 'createAdmin'},
									R.h1({}, "Admin Account")
									R.p({}, 
										"Your account's user name will be \"admin\". 
										Set and confirm a secure password."
									)
									R.div({
										className: [
											'form-group'
											'has-success has-feedback' if @state.password.length >= 5
										].join ' '
									},
										R.input({
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
											className: 'btn btn-lg btn-default'
											onClick: @_switchTab.bind null, 'index'
										},
											FaIcon('arrow-left')
											"Back"
										)
										R.button({
											className: [
												'btn btn-lg btn-success'
												'animated pulse' if @_passwordsMatch()
											].join ' '
											disabled: not @_passwordsMatch()
										}, 
											"Complete Installation"
											FaIcon('check')
										)
									)
								)
						)
					)
				)
			)

		_updatePassword: (event) ->
			@setState {password: event.target.value}

		_updatePasswordConfirmation: (event) ->
			@setState {passwordConfirmation: event.target.value}

		_passwordsMatch: ->
			return @state.password is @state.passwordConfirmation and @state.password.length > 5

		_switchTab: (newTab) ->
			# TODO: Make this some kind of flexible component/mixin
			openTab = @state.openTab
			isIndex = openTab is 'index'
			
			# Animation directions
			offDirection = if isIndex then 'Left' else 'Right'
			onDirection = if isIndex then 'Right' else 'Left'

			# Transition out oldTab
			$oldTab = $(@refs[openTab].getDOMNode())
			$oldTab.attr 'class', ('animated fadeOut' + offDirection)

			# Wait (.75 of anim default) and transition in the newTab
			setTimeout(=>
				@setState {openTab: newTab}, =>
					$newTab = $(@refs[newTab].getDOMNode())
					$newTab.attr 'class', ('animated fadeIn' + onDirection)
			, 500)

		_install: ->
			systemAccount = null

			(cb) =>
				@setState {isLoading: true}
				# Set up data directory, with subfolders from dataModels
				Persist.setUpDataDirectory Config.dataDirectory, (err) =>
					if err
						cb err
						return

					cb()
			(cb) =>
				# Generate mock "_system" admin user
				Persist.Users.Account.setUp Config.dataDirectory, (err, result) =>
					if err
						cb err
						return

					systemAccount = result
					cb()
			(cb) =>
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

	return NewInstallationPage

module.exports = {load}