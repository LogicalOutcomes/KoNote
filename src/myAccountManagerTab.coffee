# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Tab layer for managing own user account

Persist = require './persist'
Term = require './term'


load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	CrashHandler = require('./crashHandler').load(win)
	Spinner = require('./spinner').load(win)
	{FaIcon, renderName, showWhen} = require('./utils').load(win)


	MyAccountManagerTab = React.createFactory React.createClass
		displayName: 'MyAccountManagerTab'
		mixins: [React.addons.PureRenderMixin]
		# TODO: propTypes

		componentDidMount: ->
			@refs.currentPasswordField.focus()

		getInitialState: ->
			return {
				isLoading: false

				currentPassword: ''
				passwordIsVerified: false

				newPassword: ''
				newPasswordConfirm: ''
			}

		render: ->
			return R.div({id: 'myAccountManagerTab'},
				Spinner({
					isVisible: @state.isLoading
					isOverlay: true
				})
				R.div({className: 'header'},
					R.h1({}, "#{Term 'Account'} Settings")
				)
				R.div({className: 'main'},
					R.div({id: 'passwordSettings'},
						R.h3({}, "My Password")
						R.div({className: 'form-group animated'},
							R.label({}, "Verify your current password"),
							R.div({className: 'input-group'},
								R.input({
									ref: 'currentPasswordField'
									className: 'form-control'
									type: 'password'
									onChange: @_updateCurrentPassword
									value: @state.currentPassword
									placeholder: "Enter password"
									disabled: @state.passwordIsVerified
								})
								R.span({className: 'input-group-btn'},
									R.button({
										className: [
											'btn'
											'btn-primary'
											'btn-success' if @state.passwordIsVerified
										].join ' '
										disabled: (
											@state.passwordIsVerified or
											not @state.currentPassword
										)
										onClick: @_verifyCurrentPassword
									},
										if not @state.passwordIsVerified
											[
												"Verify "
												FaIcon('lock')
											]
										else
											[
												"Verified "
												FaIcon('unlock')
											]
									)
								)
							)
						)
						(if @state.passwordIsVerified
							R.div({
								id: 'newPasswordForm'
								className: 'animated fadeIn'
							},
								R.hr({})
								R.div({
									className: [
										'form-group'
										'has-success has-feedback' if @state.newPassword
									].join ' '
								},
									R.label({}, "Set your new password")
									R.input({
										ref: 'newPasswordField'
										className: 'form-control'
										type: 'password'
										value: @state.newPassword
										onChange: @_updateNewPassword
									})
									R.span({className: 'glyphicon glyphicon-ok form-control-feedback'})
								)
								R.div({
									className: [
										'form-group'
										'has-success has-feedback' unless @_newPasswordIsInvalid()
									].join ' '
								},
									R.label({}, "Confirm new password")
									R.input({
										className: 'form-control'
										type: 'password'
										value: @state.newPasswordConfirm
										onChange: @_updateNewPasswordConfirm
									})
									R.span({className: 'glyphicon glyphicon-ok form-control-feedback'})
								)
								R.hr({})
								R.div({className: 'btn-toolbar pull-right'},
									R.button({
										className: 'btn btn-default'
										onClick: @_cancelResetPassword
									}, "Cancel")
									R.button({
										className: 'btn btn-primary'
										disabled: @_newPasswordIsInvalid()
										onClick: @_resetPassword
									}, "Reset My Password")
								)
							)
						)
					)
					R.div({id: 'generalSettings'},
						# TODO: General Settings
						# R.h3({}, "General Settings")
					)
				)
			)

		_updateCurrentPassword: (event) ->
			@setState {currentPassword: event.target.value}

		_updateNewPassword: (event) ->
			@setState {newPassword: event.target.value}

		_updateNewPasswordConfirm: (event) ->
			@setState {newPasswordConfirm: event.target.value}

		_newPasswordIsInvalid: ->
			return (
				not @state.newPasswordConfirm or
				not @state.newPassword or
				@state.newPasswordConfirm isnt @state.newPassword
			)

		_cancelResetPassword: ->
			Bootbox.confirm """
				Are you sure you want to cancel resetting your password?
			""", (success) =>
				if success
					@setState @getInitialState

		_verifyCurrentPassword: ->
			@setState {isLoading: true}
			currentPassword = @state.currentPassword

			ActiveSession.account.checkPassword currentPassword, (err) =>
				@setState {isLoading: false}

				if err
					if err instanceof Persist.IOError
						Bootbox.alert """
							An error occurred.  Please check your network connection and try again.
						"""
						return

					# TODO: Figure out why this doesn't work
					if err instanceof Persist.Session.IncorrectPasswordError
						Bootbox.alert "Incorrect password. Please try again."
						return

					if err.name is 'IncorrectPasswordError'
						Bootbox.alert "Incorrect password. Please try again.", =>
							@refs.currentPasswordField.focus()
						return

					CrashHandler.handle err
					return

				# Matches user's current password
				@setState {passwordIsVerified: true}
				@refs.newPasswordField.focus()

		_resetPassword: ->
			@setState {isLoading: true}
			newPassword = @state.newPassword

			ActiveSession.account.setPassword newPassword, (err) =>
				@setState {isLoading: false}

				if err
					if err instanceof Persist.IOError
						Bootbox.alert """
							An error occurred.  Please check your network connection and try again.
						"""
						return

					CrashHandler.handle err
					return

				Bootbox.alert "Your password was successfully reset!"
				@setState @getInitialState


	return MyAccountManagerTab

module.exports = {load}
