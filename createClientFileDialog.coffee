# A dialog for allowing the user to create a new client file

Persist = require './persist'

load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	Dialog = require('./dialog').load(win)
	LayeredComponentMixin = require('./layeredComponentMixin').load(win)
	Spinner = require('./spinner').load(win)

	CreateClientFileDialog = React.createFactory React.createClass
		getInitialState: ->
			return {
				firstName: ''
				middleName: ''
				lastName: ''
				isOpen: true
			}
		render: ->
			Dialog({
				title: "Create New Client File"
				onClose: @props.onClose
			},
				R.div({className: 'createClientFileDialog'}),
					R.div({className: 'form-group'},
						R.label({}, "First name"),
						R.input({
							className: 'form-control'
							onChange: @_updateFirstName
							value: @state.firstName
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "Middle name"),
						R.input({
							className: 'form-control'
							onChange: @_updateMiddleName
							value: @state.middleName
							placeholder: "(optional)"
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "Last name"),
						R.input({
							className: 'form-control',
							onChange: @_updateLastName
							value: @state.lastName
						})
					)
					R.div({className: 'btn-toolbar'},
						R.button({
							className: 'btn btn-default'
							onClick: @_cancel							
						}, "Cancel")
						R.button({
							className: 'btn btn-primary',
							onClick: @_submit
						}, "Create client file")
					)
			)
		_cancel: ->
			@props.onCancel()
		_updateFirstName: (event) ->
			@setState {firstName: event.target.value}
		_updateLastName: (event) ->
			@setState {lastName: event.target.value}
		_submit: ->

			# More elegant way of doing this?
			if not @state.firstName or not @state.lastName
				missingNames = []
				missingNames.push "first" if not @state.firstName
				missingNames.push "middle" if not @state.middleName
				missingNames.push "last" if not @state.lastName
				Bootbox.alert "Client\'s " + missingNames.join(", ") + " name required"

			firstName = @state.firstName
			middleName = @state.middleName
			lastName = @state.lastName

			@setState {isLoading: true}
			# Need API for this to work
			# Persist.clientFile.createFile 'data', firstName, lastName, (err) =>
			# 	@setState {isLoading: false}

			# 	if err
			# 		# if err instanceof Persist.Users.UserNameTakenError
			# 		# 	Bootbox.alert "That user name is already taken."
			# 		# 	return

			# 		console.error err.stack
			# 		Bootbox.alert "An error occurred while creating the account"
			# 		return

			@props.onSuccess()

	return CreateClientFileDialog

module.exports = {load}
