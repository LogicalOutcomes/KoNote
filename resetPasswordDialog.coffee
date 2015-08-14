# A dialog for resetting a user password (admin only)

Persist = require './persist'

load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	Config = require('./config')
	Term = require('./term')
	CrashHandler = require('./crashHandler').load(win)
	Dialog = require('./dialog').load(win)
	LayeredComponentMixin = require('./layeredComponentMixin').load(win)
	Spinner = require('./spinner').load(win)	

	ResetPasswordDialog = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]
		getInitialState: ->
			return {
				userName: ''
				password: ''
				confirmPassword: ''
				isLoading: false
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
						R.label({}, "User name"),
						R.input({
							className: 'form-control'
							onChange: @_updateUserName
							value: @state.userName
						})
					)
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
		_updateUserName: (event) ->
			@setState {userName: event.target.value}
			# new syntax: @setState => userName: event.target.value
		_updatePassword: (event) ->
			@setState {password: event.target.value}
		_updateConfirmPassword: (event) ->
			@setState {confirmPassword: event.target.value}
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
			
			unless @state.password is @state.confirmPassword
				Bootbox.alert "Passwords do not match!"
				return

			userName = @state.userName
			password = @state.password

			@setState {isLoading: true}
			Persist.Users.resetAccountPassword Config.dataDirectory, userName, password, (err) =>
				@setState {isLoading: false}

				if err
					if err instanceof Persist.Users.UnknownUserNameError
						Bootbox.alert "Unknown user! Please check user name and try again"
						return

					if err instanceof Persist.Users.AccountDeactivatedError
						Bootbox.alert "The specified user account has been permanently deactivated."
						return

					CrashHandler.handle err
					return

				Bootbox.alert
					message: "Password reset for \"#{userName}\""
					callback: =>
						@props.onSuccess()

	return ResetPasswordDialog

module.exports = {load}
