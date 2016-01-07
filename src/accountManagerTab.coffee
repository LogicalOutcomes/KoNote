# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

Async = require 'async'
_ = require 'underscore'
Imm = require 'immutable'
Persist = require './persist'

load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	Config = require './config'
	Term = require('./term')
	CrashHandler = require('./crashHandler').load(win)
	Dialog = require('./dialog').load(win)
	OrderableTable = require('./orderableTable').load(win)
	OpenDialogLink = require('./openDialogLink').load(win)
	Spinner = require('./spinner').load(win)	
	{FaIcon, showWhen} = require('./utils').load(win)

	AccountManagerTab = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				mode: 'loading' # loading, ready, or working
				openDialogId: null
				userAccounts: Imm.List()
			}

		componentDidMount: ->
			# Load Users' publicInfo, since it's not passed down from clientSelectionPage
			userNames = null
			userAccounts = null

			Async.series [
				(cb) =>
					Persist.Users.listUserNames Config.dataDirectory, (err, result) =>
						if err
							cb err
							return

						userNames = result
						cb()
				(cb) =>
					Async.map userNames.toArray(), (userName, cb) =>

						Persist.Users.Account.read Config.dataDirectory, userName, (err, result) =>
							if err
								cb err
								return

							# Build object with only userName and publicInfo
							userAccountObject = @_buildUserAccountObject(result)
						
							cb null, userAccountObject

					, (err, results) =>
						userAccounts = Imm.List(results)
						cb()

			], (err) =>
				if err
					CrashHandler.handle err
					return

				@setState {userAccounts}

		render: ->
			return R.div({
				className: 'accountManagerTab'
			},
				R.div({className: 'header'},
					R.h1({}, Term 'User Accounts')
				)
				R.div({className: 'main'},
					OrderableTable({
						tableData: @state.userAccounts
						rowKey: ['userName']
						rowIsVisible: (row) =>
							return row.getIn(['publicInfo', 'isActive'])
						columns: [
							{
								name: "User Name"
								dataPath: ['userName']
							}
							{
								name: "Account Type"
								dataPath: ['publicInfo', 'accountType']
							}
							{
								name: "Options"
								nameIsVisible: false
								buttons: [
									{
										className: 'btn btn-default'
										text: "Reset Password"
										# icon: 'key'
										dialog: ResetPasswordDialog
									}
									{
										className: 'btn btn-danger'
										text: "Deactivate"
										# icon: 'user'
										onClick: (dataPoint) =>
											userName = dataPoint.get('userName')

											@_deactivateAccount.bind null, userName, =>
												# Remove userAccount
												userAccounts = @state.userAccounts
												.filter (userAccount) => userAccount.get('userName') isnt userName
												# Restore state
												@setState {userAccounts}
									}									
								]
							}
						]
					})
				)
				R.div({className: 'optionsMenu'},
					OpenDialogLink({
						className: 'btn btn-lg btn-primary'
						dialog: CreateAccountDialog
						onSuccess: (userAccount) =>
							# Push in new userAccount manually,
							# because not listening for it on pageComponent
							newAccount = @_buildUserAccountObject(userAccount)
							userAccounts = @state.userAccounts.push newAccount
							@setState {userAccounts}
					},
						FaIcon('plus')
						" New #{Term 'Account'}"
					)
				)
			)		

		_buildUserAccountObject: (userAccount) ->
			return Imm.fromJS {
				userName: userAccount.userName
				publicInfo: userAccount.publicInfo
			}

		_openCreateAccountDialog: ->
			@setState {
				openDialogId: 'createAccount'
			}

		_openResetPasswordDialog: (userName) ->
			@setState {
				openDialogId: 'resetPassword'
				selectedUserName: userName
			}

		_deactivateAccount: (userName, cb) ->
			if userName is global.ActiveSession.userName
				Bootbox.alert "Accounts cannot deactivate themselves.  Try logging in using a different account."
				return

			Bootbox.confirm "Permanently deactivate #{userName}?", (result) =>
				unless result is true
					return

				@setState {mode: 'working'}

				Persist.Users.Account.read Config.dataDirectory, userName, (err, acc) =>
					if err
						if err instanceof Persist.Users.UnknownUserNameError
							Bootbox.alert "No account exists with this user name."
							return

						cb err
						return

					acc.deactivate (err) =>
						@setState {mode: 'ready'}

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

						cb()
						Bootbox.alert "The account #{userName} has been deactivated."

		_closeDialog: ->
			@setState {
				openDialogId: null
				selectedUserName: null
			}

	CreateAccountDialog = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]
		getInitialState: ->
			return {
				userName: ''
				password: ''
				passwordConfirm: ''

				isAdmin: false
				isLoading: false
			}

		componentDidMount: ->
			@refs.userNameField.focus()

		render: ->
			Dialog({
				ref: 'dialog'
				title: "Create new #{Term 'account'}"
				onClose: @_cancel
			},
				R.div({id: 'createAccountDialog'},
					R.div({className: 'form-group'},
						R.label({}, "User name"),
						R.input({
							ref: 'userNameField'
							className: 'form-control'
							onChange: @_updateUserName
							value: @state.userName
						})
					)
					R.div({
						className: [
							'form-group'
							'has-success has-feedback' if @state.password
						].join ' '
					},
						R.label({}, "Set Password")
						R.input({
							className: 'form-control'
							type: 'password'
							onChange: @_updatePassword
							value: @state.password
						})
						R.span({className: 'glyphicon glyphicon-ok form-control-feedback'})
					)
					R.div({
						className: [
							'form-group'
							'has-success has-feedback' if (
								@state.passwordConfirm and
								@state.passwordConfirm is @state.password
							)
						].join ' '
					},
						R.label({}, "Confirm Password")
						R.input({
							className: 'form-control'
							type: 'password'
							onChange: @_updatePasswordConfirm
							value: @state.passwordConfirm
						})
						R.span({className: 'glyphicon glyphicon-ok form-control-feedback'})
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
							disabled: (
								not @state.userName or
								not @state.password or
								not @state.passwordConfirm or
								@state.password isnt @state.passwordConfirm
							)
						}, "Create #{Term 'Account'}")
					)
				)
			)		
		_updateUserName: (event) ->
			@setState {userName: event.target.value}
		_updatePassword: (event) ->
			@setState {password: event.target.value}
		_updatePasswordConfirm: (event) ->
			@setState {passwordConfirm: event.target.value}
		_updateIsAdmin: (event) ->
			@setState {isAdmin: event.target.checked}
			
		_cancel: ->
			@props.onCancel()
		_submit: ->
			unless /^[a-zA-Z0-9_-]+$/.exec @state.userName
				Bootbox.alert "User name must contain only letters, numbers, underscores, and dashes."
				return

			userName = @state.userName
			password = @state.password
			accountType = if @state.isAdmin then 'admin' else 'normal'

			@refs.dialog.setIsLoading true

			Persist.Users.Account.create global.ActiveSession.account, userName, password, accountType, (err, result) =>
				@refs.dialog.setIsLoading(false) if @refs.dialog?

				if err
					if err instanceof Persist.Users.UserNameTakenError
						Bootbox.alert "That user name is already taken."
						return

					CrashHandler.handle err
					return

				newAccount = result
				@props.onSuccess(newAccount)
				@props.onCancel()

	ResetPasswordDialog = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]
		getInitialState: ->
			return {
				isLoading: false
				password: ''
				confirmPassword: ''
			}
		render: ->
			return Dialog({
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
							disabled: not @state.password or not @state.confirmPassword
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
			# First catch unmatched passwords
			unless @state.password is @state.confirmPassword
				Bootbox.alert "Passwords do not match!"
				return

			userName = @props.rowData.get('userName')
			password = @state.password

			@setState {isLoading: true}

			acc = null
			decryptedAcc = null

			Async.series [
				(cb) =>
					Persist.Users.Account.read Config.dataDirectory, userName, (err, result) =>
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

	return AccountManagerTab

module.exports = {load}
