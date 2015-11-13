# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

Async = require 'async'

Persist = require './persist'
Account = Persist.Users.Account

load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	Config = require './config'
	Term = require('./term')
	CrashHandler = require('./crashHandler').load(win)
	Dialog = require('./dialog').load(win)
	LayeredComponentMixin = require('./layeredComponentMixin').load(win)
	Spinner = require('./spinner').load(win)	
	{FaIcon, showWhen} = require('./utils').load(win)

	AccountManagerDialog = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin, LayeredComponentMixin]

		getInitialState: ->
			return {
				mode: 'loading' # loading, ready, or working
				openDialogId: null
				userNames: null
			}

		render: ->
			Dialog({
				title: "#{Term 'Account'} Manager"
				onClose: @props.onCancel
			},
				R.div({className: 'accountManagerDialog'},
					Spinner({
						isVisible: @state.mode in ['loading', 'working']
						isOverlay: true
					})
					if @state.mode in ['ready', 'working']
						R.div({},
							R.div({className: 'btn-toolbar'},
								R.button({
									className: 'btn btn-primary'
									onClick: @_openCreateAccountDialog
								},
									FaIcon('plus')
									" New User"
								)
							)

							R.table({className: 'userTable table table-striped'},
								R.tbody({},
									(@state.userNames.sort().map (userName) =>
										R.tr({},
											R.td({className: 'userNameCell'}, userName)
											R.td({className: 'buttonsCell'},
												R.div({className: 'btn-group'},
													(if userName isnt global.ActiveSession.userName
														R.button({
															className: 'btn btn-default'
															onClick: @_openResetPasswordDialog.bind null, userName
														},
															"Reset password"
														)
													)
													(if userName isnt global.ActiveSession.userName
														R.button({
															className: 'btn btn-danger'
															onClick: @_deactivateAccount.bind null, userName
														},
															"Deactivate"
														)
													)
												)
											)
										)
									).toArray()...
								)
							)
						)
				)
			)

		renderLayer: ->
			switch @state.openDialogId
				when 'createAccount'
					return CreateAccountDialog({
						onClose: @_closeDialog
						onCancel: @_closeDialog
						onSuccess: (userName) =>
							@_closeDialog()
							@setState (s) -> {
								userNames: s.userNames.push(userName)
							}
					})
				when 'resetPassword'
					return ResetPasswordDialog({
						userName: @state.selectedUserName
						onClose: @_closeDialog
						onCancel: @_closeDialog
						onSuccess: @_closeDialog
					})
				when null
					return R.div()
				else
					throw new Error "Unknown dialog ID: #{JSON.stringify @state.openDialogId}"

		componentDidMount: ->
			Persist.Users.listUserNames Config.dataDirectory, (err, userNames) =>
				if err
					CrashHandler.handle err
					return

				@setState (s) -> {
					mode: 'ready'
					userNames
				}

		_openCreateAccountDialog: ->
			@setState (s) -> {
				openDialogId: 'createAccount'
			}

		_openResetPasswordDialog: (userName) ->
			@setState (s) -> {
				openDialogId: 'resetPassword'
				selectedUserName: userName
			}

		_deactivateAccount: (userName) ->
			if userName is global.ActiveSession.userName
				Bootbox.alert "Accounts cannot deactivate themselves.  Try logging in using a different account."
				return

			Bootbox.confirm "Permanently deactivate #{userName}?", (result) =>
				unless result is true
					return

				@setState (s) -> {mode: 'working'}

				Account.read Config.dataDirectory, userName, (err, acc) =>
					if err
						if err instanceof Persist.Users.UnknownUserNameError
							Bootbox.alert "No account exists with this user name."
							return

						cb err
						return

					acc.deactivate (err) =>
						@setState (s) -> {mode: 'ready'}

						if err
							if err instanceof Persist.Users.DeactivatedAccountError
								Bootbox.alert "This account is already deactivated."
								return

							# BEGIN v1.3.1 migration
							if err.message is "cannot deactivate accounts in old format"
								# To deactivate an old-style account, just
								# reset the account's password, then deactivate
								# it.
								Bootbox.alert "Please contact KoNode support for assistance in deactivating this account."
								return
							# END v1.3.1 migration

							CrashHandler.handle err
							return

						Bootbox.alert "The account #{userName} has been deactivated."

		_closeDialog: ->
			@setState (s) -> {
				openDialogId: null
				selectedUserName: null
			}

	CreateAccountDialog = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]
		getInitialState: ->
			return {
				userName: ''
				password: ''
				isAdmin: false
				isLoading: false
			}
		render: ->
			Dialog({
				title: "Create new #{Term 'account'}"
				onClose: @_cancel
			},
				R.div({className: 'createAccountDialog'},
					Spinner({
						isVisible: @state.isLoading
						isOverlay: true
					})
					R.div({className: 'form-group'},
						R.label({}, "User name"),
						R.input({
							className: 'form-control'
							onChange: @_updateUserName
							value: @state.userName
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "Password"),
						R.input({
							className: 'form-control'
							type: 'password'
							onChange: @_updatePassword
							value: @state.password
						})
					)
					R.div({className: 'checkbox'},
						R.label({},
							R.input({
								type: 'checkbox'
								onChange: @_updateIsAdmin
								checked: @state.isAdmin
							}),
							"Give this user administrative powers"
						)
					)
					R.div({className: 'btn-toolbar'},
						R.button({
							className: 'btn btn-default'
							onClick: @_cancel
						}, "Cancel"),
						R.button({
							className: 'btn btn-primary'
							onClick: @_submit
						}, "Create #{Term 'Account'}")
					)
				)
			)
		_cancel: ->
			@props.onCancel()
		_updateUserName: (event) ->
			@setState {userName: event.target.value}
		_updatePassword: (event) ->
			@setState {password: event.target.value}
		_updateIsAdmin: (event) ->
			@setState {isAdmin: event.target.checked}
		_submit: ->
			unless @state.userName
				Bootbox.alert "User name is required"
				return

			unless /^[a-zA-Z0-9_-]+$/.exec @state.userName
				Bootbox.alert "User name must contain only letters, numbers, underscores, and dashes."
				return

			unless @state.password
				Bootbox.alert "Password is required"
				return

			userName = @state.userName
			password = @state.password
			accountType = if @state.isAdmin then 'admin' else 'normal'

			@setState {isLoading: true}
			Account.create global.ActiveSession.account, userName, password, accountType, (err) =>
				@setState {isLoading: false}

				if err
					if err instanceof Persist.Users.UserNameTakenError
						Bootbox.alert "That user name is already taken."
						return

					CrashHandler.handle err
					return

				@props.onSuccess(userName)

	ResetPasswordDialog = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]
		getInitialState: ->
			return {
				isLoading: false
				password: ''
				confirmPassword: ''
			}
		render: ->
			Dialog({
				title: "Reset user password"
				onClose: @_cancel
			},
				R.div({className: 'ResetPasswordDialog'},
					Spinner({
						isVisible: @state.isLoading
						isOverlay: true
					})
					R.div({className: 'form-group'},
						R.label({}, "New password"),
						R.input({
							className: 'form-control'
							type: 'password'
							onChange: @_updatePassword
							value: @state.password
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "Confirm password"),
						R.input({
							className: 'form-control'
							type: 'password'
							onChange: @_updateConfirmPassword
							value: @state.confirmPassword
						})
					)
					R.div({className: 'btn-toolbar'},
						R.button({
							className: 'btn btn-default'
							onClick: @_cancel
						}, "Cancel"),
						R.button({
							className: 'btn btn-primary'
							onClick: @_submit
						}, "Reset Password")
					)
				)
			)
		_cancel: ->
			@props.onCancel()
		_updatePassword: (event) ->
			@setState {password: event.target.value}
		_updateConfirmPassword: (event) ->
			@setState {confirmPassword: event.target.value}
		_submit: ->
			unless @state.password
				Bootbox.alert "Password is required"
				return

			unless @state.password is @state.confirmPassword
				Bootbox.alert "Passwords do not match!"
				return

			userName = @props.userName
			password = @state.password

			@setState {isLoading: true}

			acc = null
			decryptedAcc = null

			Async.series [
				(cb) =>
					Account.read Config.dataDirectory, userName, (err, result) =>
						if err
							if err instanceof Persist.Users.UnknownUserNameError
								Bootbox.alert "Unknown user! Please check user name and try again"
								return

							cb err
							return

						acc = result
						cb()
				(cb) =>
					acc.decryptWithSystemKey global.ActiveSession.account, (err, result) =>
						if err
							if err instanceof Persist.Users.DeactivatedAccountError
								Bootbox.alert "The specified user account has been deactivated."
								return

							cb err
							return

						decryptedAcc = result
						cb()
				(cb) =>
					decryptedAcc.setPassword password, cb
			], (err) =>
				@setState {isLoading: false}

				if err
					CrashHandler.handle err
					return

				Bootbox.alert
					message: "Password reset for \"#{userName}\""
					callback: =>
						@props.onSuccess()

	return AccountManagerDialog

module.exports = {load}
