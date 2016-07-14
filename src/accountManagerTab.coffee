# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

Async = require 'async'
_ = require 'underscore'
Imm = require 'immutable'
ImmPropTypes = require 'react-immutable-proptypes'

Persist = require './persist'
Config = require './config'
Term = require './term'

load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	{PropTypes} = React
	R = React.DOM

	CrashHandler = require('./crashHandler').load(win)
	Dialog = require('./dialog').load(win)
	OrderableTable = require('./orderableTable').load(win)
	OpenDialogLink = require('./openDialogLink').load(win)
	Spinner = require('./spinner').load(win)
	ColorKeyBubble = require('./colorKeyBubble').load(win)
	UserProgramDropdown = require('./userProgramDropdown').load(win)

	{FaIcon, showWhen, stripMetadata} = require('./utils').load(win)

	AccountManagerTab = React.createFactory React.createClass
		displayName: 'AccountManagerTab'
		mixins: [React.addons.PureRenderMixin]

		propTypes: {
			userProgramLinks: ImmPropTypes.list
		}

		getInitialState: ->
			return {
				userAccounts: Imm.List()

				openDialogId: null
				displayDeactivated: false
			}

		componentWillMount: ->
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
			# Tack on program assignment to userAccounts
			userAccounts = @state.userAccounts.map (userAccount) =>
				userName = userAccount.get('userName')

				programLink = @props.userProgramLinks.find (link) ->
					userName is link.get('userName') and link.get('status') is 'assigned'

				return userAccount unless programLink?

				matchingProgram = @props.programs.find (program) ->
					program.get('id') is programLink.get('programId')

				return userAccount.set 'program', matchingProgram

			# Filter out deactivated accounts
			if userAccounts? and not @state.displayDeactivated
				userAccounts = userAccounts.filter (userAccount) ->
					userAccount.getIn(['publicInfo', 'isActive'])


			R.div({className: 'accountManagerTab'},
				R.div({className: 'header'},
					R.h1({},
						R.span({id: 'toggleDisplayDeactivated'},
							R.div({className: 'checkbox'},
								R.label({},
									R.input({
										type: 'checkbox'
										checked: @state.displayDeactivated
										onClick: @_toggleDisplayDeactivated
									})
									"Show deactivated"
								)
							)
						)
						Term 'User Accounts'
					)
				)
				R.div({className: 'main'},
					R.div({id: 'userAccountsContainer'},
						OrderableTable({
							tableData: userAccounts
							openDialog: {
								dialog: ModifyAccountDialog
								props: {
									programs: @props.programs
									userProgramLinks: @props.userProgramLinks
									updateUserProgramLinks: @_updateUserProgramLinks
									updateAccount: @_updateAccount
								}
							}
							sortByData: ['userName']
							rowKey: ['userName']
							rowClass: (dataPoint) ->
								'deactivatedAccount' unless dataPoint.getIn(['publicInfo', 'isActive'])
							columns: [
								{
									name: "Colour Key"
									nameIsVisible: false
									dataPath: ['program']
									cellClass: 'colorKeyCell'
									value: (dataPoint) ->
										program = dataPoint.get('program')

										ColorKeyBubble({
											colorKeyHex: program.get('colorKeyHex')
											popover: {
												title: program.get('name')
												content: program.get('description')
											}
										})
								}
								{
									name: "User Name"
									dataPath: ['userName']
								}
								{
									name: "Account Type"
									dataPath: ['publicInfo', 'accountType']
								}
							]
						})
					)
				)
				R.div({className: 'optionsMenu'},
					OpenDialogLink({
						className: 'btn btn-lg btn-primary'
						dialog: CreateAccountDialog
						programs: @props.programs
						onSuccess: @_addAccount
					},
						FaIcon('plus')
						" New #{Term 'Account'}"
					)
				)
			)

		_toggleDisplayDeactivated: ->
			displayDeactivated = not @state.displayDeactivated
			@setState {displayDeactivated}

		_buildUserAccountObject: (userAccount) ->
			return Imm.fromJS {
				userName: userAccount.userName
				publicInfo: userAccount.publicInfo
			}

		_addAccount: (userAccount) ->
			newAccount = @_buildUserAccountObject(userAccount)
			userAccounts = @state.userAccounts.push newAccount

			@setState {userAccounts}

		_updateAccount: (userAccount, cb=(->)) ->
			matchingUserAccount = @state.userAccounts.find (account) ->
				account.getIn(['publicInfo', 'userName']) is userAccount.getIn(['publicInfo', 'userName'])

			userAccountIndex = @state.userAccounts.indexOf matchingUserAccount
			userAccounts = @state.userAccounts.set userAccountIndex, userAccount

			@setState {userAccounts}, cb


	ModifyAccountDialog = React.createFactory React.createClass
		displayName: 'ModifyAccountDialog'
		mixins: [React.addons.PureRenderMixin]

		propTypes: {
			dataPoint: ImmPropTypes.map
			programs: ImmPropTypes.list
			userProgramLinks: ImmPropTypes.list
			updateAccount: PropTypes.func
		}

		getInitialState: -> {
			actionComponent: null
			actionTitle: null
			userProgram: null
		}

		render: ->
			userAccount = @props.dataPoint
			# Dialogs are a new React instance, so don't change with new props
			# userProgram = @state.userProgram or userAccount.get('program')
			userProgram = userAccount.get('program')

			isAdmin = userAccount.getIn(['publicInfo', 'accountType']) is 'admin'
			isDeactivated = not userAccount.getIn(['publicInfo', 'isActive'])

			# Append actionTitle to the dialog title if exists
			title = R.span({},
				"Modify #{if isDeactivated then 'Deactivated' else ''} Account"
				(if @state.actionComponent?
					R.span({},
						' '
						FaIcon('long-arrow-right')
						' '
						@state.actionTitle
					)
				)
			)

			return Dialog({
				ref: 'dialog'
				title
				onClose: @props.onClose
			},
				R.div({id: 'modifyAccountDialog'},

					R.section({id: 'accountDetails'},
						R.div({id: 'avatar'},
							R.div({id: 'avatar'},
								FaIcon((if isDeactivated then 'user-times' else 'user'), {
									style:
										background: userAccount.getIn(['program', 'colorKeyHex'])
								})
							)
							R.h3({},
								userAccount.get('userName')
								" (admin)" if isAdmin
							)
							R.div({id: 'userProgram'},
								UserProgramDropdown({
									ref: 'userProgramDropdown'
									id: 'modifyUserProgramDropdown'
									userProgram: userProgram
									programs: @props.programs
									onSelect: @_reassignProgram
								})
							)
						)
					)

					R.section({id: 'accountActions'},
						(switch @state.actionComponent
							when 'resetPassword'
								ResetPasswordView({
									userName: userAccount.get('userName')
									setIsLoading: @refs.dialog.setIsLoading
									onCancel: @_closeActionComponent
									onSuccess: @_closeActionComponent
								})
							else
								R.div({id: 'actionsList'},
									R.h4({}, "Account Actions")
									R.ul({},
										R.li({},
											R.button({
												className: 'btn btn-link'
												onClick: @_switchActionComponent.bind(
													null, 'resetPassword', "Reset Password"
												)
											}, "Reset Password")
										)
										R.li({},
											R.button({
												className: 'btn btn-link'
												onClick: @_toggleUserProgramDropdown
											}, "Re-Assign #{Term 'Program'}")
										)
										R.li({},
											R.button({
												className: 'btn btn-link'
												onClick: @_changeAccountType.bind null, userAccount
											}, "Change Account Type")
										)
										R.li({},
											R.button({
												className: 'btn btn-link'
												onClick: @_deactivateAccount.bind null, userAccount
											}, "Deactivate Account")
										)
									)
								)
						)
					)
				)
			)

		_switchActionComponent: (actionComponent, actionTitle) ->
			@setState {actionComponent, actionTitle}

		_closeActionComponent: ->
			@_switchActionComponent null, null

		_toggleUserProgramDropdown: ->
			@refs.userProgramDropdown.toggle()

		_changeAccountType: (userAccount, isAdmin) ->
			userName = userAccount.get('userName')
			isAdmin = userAccount.getIn(['publicInfo', 'accountType']) is 'admin'

			newAccountType = if isAdmin then 'normal' else 'admin'

			dataDirectory = global.ActiveSession.account.dataDirectory
			userAccountOp = null
			decryptedUserAccount = null

			Async.series [
				(cb) =>
					action = if newAccountType is 'admin' then "Grant" else "Revoke"

					Bootbox.confirm "#{action} admin privileges for #{userName}?", (ok) =>
						cb() if ok
						return

				(cb) =>
					Persist.Users.Account.read dataDirectory, userName, (err, account) =>
						if err
							cb err
							return

						userAccountOp = account
						cb()

				(cb) =>
					userAccountOp.decryptWithSystemKey global.ActiveSession.account, (err, result) =>
						if err
							cb err
							return

						decryptedUserAccount = result
						cb()

				(cb) =>
					decryptedUserAccount.changeAccountType decryptedUserAccount, global.ActiveSession.account, newAccountType, (err) =>
						if err
							cb err
							return
						cb()

			], (err) =>
				if err
					if err instanceof Persist.IOError
						Bootbox.alert "Please check your network connection and try again."
						return

					if err instanceof Persist.Users.AccountTypeError
						Bootbox.alert {
							title: "Error modifying account"
							message: err.message
						}
						return

					CrashHandler.handle err
					return

				# Success
				userAccount = userAccount.setIn(['publicInfo', 'accountType'], newAccountType)

				@props.updateAccount userAccount, ->
					action = if newAccountType is 'admin' then "granted to" else "revoked from"
					Bootbox.alert "Administrator privileges #{action} #{userName}."

		_reassignProgram: (newProgram) ->
			userAccount = @props.dataPoint
			userAccountProgramId = userAccount.getIn(['program', 'id'])

			# Ignore when same program is selected
			return if newProgram.get('id') is userAccountProgramId

			userName = @props.dataPoint.get('userName')

			# Unassign any existing 'assigned' userProgramLinks
			# Note that these are actually userProgramLinkHeaders (indexes), so may be incomplete in future
			unassignedLinks = @props.userProgramLinks
			.filter (link) -> link.get('userName') is userName and link.get('status') is 'assigned'
			.map (link) -> stripMetadata link.set('status', 'unassigned')

			# Check for a pre-existing link, so we only have to revise (assign) it
			existingLink = @props.userProgramLinks.find (link) ->
				link.get('userName') is userName and link.get('programId') is newProgram.get('id')

			userProgramLink = null

			Async.series [
				(cb) =>
					Async.each unassignedLinks.toArray(), (link, cb) ->
						global.ActiveSession.persist.userProgramLinks.createRevision link, cb
					, cb

				(cb) =>
					if existingLink?
						userProgramLink = stripMetadata existingLink.set('status', 'assigned')

						global.ActiveSession.persist.userProgramLinks.createRevision userProgramLink, cb
					else
						userProgramLink = Imm.fromJS {
							userName
							programId: newProgram.get('id')
							status: 'assigned'
						}
						global.ActiveSession.persist.userProgramLinks.create userProgramLink, cb

			], (err) =>
				if err
					if err instanceof Persist.IOError
						Bootbox.alert "Please check your network connection and try again."
						return

					CrashHandler.handle err
					return

				# Success
				# userProgramLinks updated eventListeners on clientSelectionPage
				Bootbox.alert "Assigned #{userName} to #{Term 'program'}: <b>#{newProgram.get('name')}</b>"

		_deactivateAccount: (userAccount) ->
			userName = userAccount.get('userName')

			if userName is global.ActiveSession.userName
				Bootbox.alert "Accounts cannot deactivate themselves.  Try logging in using a different account."
				return

			dataDirectory = global.ActiveSession.account.dataDirectory
			userAccountOp = null

			Async.series [
				(cb) =>
					Bootbox.confirm "Permanently deactivate #{userName}?", (result) =>
						cb() if result
						return

				(cb) =>
					Persist.Users.Account.read dataDirectory, userName, (err, account) =>
						if err
							cb err
							return

						userAccountOp = account
						cb()

				(cb) =>
					userAccountOp.deactivate (err) =>
						if err
							cb err
							return

						cb()

			], (err) =>
				if err
					if err instanceof Persist.IOError
						Bootbox.alert "Please check your network connection and try again."
						return

					if err instanceof Persist.Users.UnknownUserNameError
						Bootbox.alert "No account exists with this user name."
						return

					if err instanceof Persist.Users.DeactivatedAccountError
						Bootbox.alert "This account is already deactivated."
						return

					CrashHandler.handle err
					return

				# Success
				userAccount = userAccount.setIn(['publicInfo', 'isActive'], false)

				@props.updateAccount userAccount, ->
					Bootbox.alert "The account #{userName} has been deactivated."


	CreateAccountDialog = React.createFactory React.createClass
		displayName: 'CreateAccountDialog'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				userName: ''
				password: ''
				passwordConfirm: ''
				programId: ''
				isAdmin: false
			}

		componentDidMount: ->
			@refs.userNameField.focus()

		render: ->
			Dialog({
				ref: 'dialog'
				title: "Create new #{Term 'account'}"
				onClose: @_cancel
			},
				R.div({className: 'createAccountDialog'},
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
					R.div({className: 'form-group'},
						R.label({}, "Assign to #{Term 'Program'}")
						R.div({id: 'programsContainer'},
							"No #{Term 'programs'} exist yet" if @props.programs.isEmpty()
							(@props.programs.map (program) =>
								isSelected = @state.programId is program.get('id')

								R.button({
									className: 'btn btn-default programOptionButton'
									onClick: @_updateProgramId.bind null, program.get('id')
									key: program.get('id')
								},
									ColorKeyBubble({
										isSelected
										colorKeyHex: program.get('colorKeyHex')
									})
									program.get('name')
								)
							)
						)
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

		_updateProgramId: (programId) ->
			if programId is @state.programId then programId = ''
			@setState {programId}

		_updateIsAdmin: (event) ->
			@setState {isAdmin: event.target.checked}

		_cancel: ->
			@props.onCancel()

		_submit: ->
			@refs.dialog.setIsLoading true

			userName = @state.userName
			password = @state.password
			programId = @state.programId
			accountType = if @state.isAdmin then 'admin' else 'normal'

			adminAccount = global.ActiveSession.account
			newAccount = null

			Async.series [
				(cb) =>
					# Create the account
					Persist.Users.Account.create adminAccount, userName, password, accountType, (err, result) =>
						if err
							cb err
							return

						newAccount = result
						cb()

				(cb) =>
					# Create user program link (if any)
					if not programId
						cb()
						return

					userProgramLink = Imm.fromJS {
						status: 'assigned'
						userName
						programId
					}

					global.ActiveSession.persist.userProgramLinks.create userProgramLink, cb

			], (err) =>
				@refs.dialog.setIsLoading(false) if @refs.dialog?

				if err
					if err instanceof Persist.Users.UserNameTakenError
						Bootbox.alert "That user name is already taken."
						return

					if err instanceof Persist.Users.InvalidUserNameError
						Bootbox.alert "User name must contain only letters, numbers, underscores, and dashes."
						return

					if err instanceof Persist.IOError
						console.error err
						Bootbox.alert """
							Please check your network connection and try again.
						"""
						return

					CrashHandler.handle err
					return

				# Manually deliver successfully created account to managerTab
				@props.onSuccess(newAccount)


	ResetPasswordView = React.createFactory React.createClass
		displayName: 'ResetPasswordView'
		mixins: [React.addons.PureRenderMixin]

		propTypes: {
			onCancel: PropTypes.func.isRequired
			onSuccess: PropTypes.func.isRequired
			userName: PropTypes.string.isRequired
		}

		getInitialState: ->
			return {
				password: ''
				confirmPassword: ''
			}

		componentDidMount: ->
			@refs.password.focus()

		render: ->
			formIsValid = @_formIsValid()


			R.div({className: 'resetPasswordDialog'},

				R.div({
					className: [
						'form-group'
						'has-feedback has-success' if @state.password
					].join ' '
				},
					R.label({}, "New password"),
					R.input({
						ref: 'password'
						className: 'form-control'
						type: 'password'
						onChange: @_updatePassword
						value: @state.password
					})
					R.span({
						className: [
							'glyphicon'
							'glyphicon-ok' if @state.password
							'form-control-feedback'
						].join ' '
					})
				)

				R.div({
					className: [
						'form-group'
						'has-feedback' if @state.confirmPassword
						'has-warning' if @state.confirmPassword and not formIsValid
						'has-success' if formIsValid
					].join ' '
				},
					R.label({}, "Confirm password"),
					R.input({
						className: 'form-control'
						type: 'password'
						onChange: @_updateConfirmPassword
						value: @state.confirmPassword
					})
					R.span({
						className: [
							'glyphicon'
							'glyphicon-warning-sign' if @state.confirmPassword and not formIsValid
							'glyphicon-ok' if formIsValid
							'form-control-feedback'
						].join ' '
					})
				)

				R.div({className: 'buttonToolbar'},
					R.div({},
						R.button({
							className: 'btn btn-default'
							onClick: @props.onCancel
						},
							"Cancel"
						)
					)
					R.div({},
						R.button({
							className: 'btn btn-primary'
							onClick: @_submit
							disabled: not formIsValid
						},
							"Reset Password"
						)
					)
				)

			)

		_formIsValid: ->
			@state.password and @state.confirmPassword and @state.confirmPassword is @state.password

		_updatePassword: (event) ->
			@setState {password: event.target.value}

		_updateConfirmPassword: (event) ->
			@setState {confirmPassword: event.target.value}

		_submit: ->
			# First catch unmatched passwords
			unless @state.password is @state.confirmPassword
				Bootbox.alert "Passwords do not match"
				return

			@props.setIsLoading true

			dataDirectory = global.ActiveSession.account.dataDirectory
			password = @state.password

			userAccount = null
			decryptedUserAccount = null

			Async.series [
				(cb) =>
					Persist.Users.Account.read dataDirectory, @props.userName, (err, result) =>
						if err
							cb err
							return

						userAccount = result
						cb()

				(cb) =>
					userAccount.decryptWithSystemKey global.ActiveSession.account, (err, result) =>
						if err
							cb err
							return

						decryptedUserAccount = result
						cb()

				(cb) =>
					decryptedUserAccount.setPassword password, cb

			], (err) =>
				@props.setIsLoading false

				if err
					if err instanceof Persist.Users.UnknownUserNameError
						Bootbox.alert "Unknown user! Please check user name and try again"
						return

					if err instanceof Persist.IOError
						console.error err
						Bootbox.alert """
							Please check your network connection and try again.
						"""
						return

					if err instanceof Persist.Users.DeactivatedAccountError
						Bootbox.alert "The specified user account has been deactivated."
						return

					CrashHandler.handle err
					return

				Bootbox.alert "Password reset for \"#{@props.userName}\"", @props.onSuccess


	return AccountManagerTab

module.exports = {load}
