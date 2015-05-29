# A dialog for allowing the user to define (i.e. create) a new metric

Persist = require './persist'

load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	Dialog = require('./dialog').load(win)
	LayeredComponentMixin = require('./layeredComponentMixin').load(win)
	Spinner = require('./spinner').load(win)

	# Upcoming features:
	# 			# - a user table
	# 			#   - account type
	# 			#   - delete account button
	# 			#   - change password button
	# 			# - export?

	CreateAccountDialog = React.createFactory React.createClass
		getInitialState: ->
			return {
				userName: ''
				password: ''
				isAdmin: false
				isLoading: false
			}
		render: ->
			Dialog({
				title: "Create new account"
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
						}, "Create account")
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

			# TODO where to get data dir?
			@setState {isLoading: true}
			Persist.Users.createAccount 'data', userName, password, accountType, (err) =>
				@setState {isLoading: false}

				if err
					if err instanceof Persist.Users.UserNameTakenError
						Bootbox.alert "That user name is already taken."
						return

					console.error err.stack
					Bootbox.alert "An error occurred while creating the account"
					return

				@props.onSuccess()

	return CreateAccountDialog

module.exports = {load}
