# A dialog for allowing the user to create a new client file

Persist = require './persist'
Imm = require 'immutable'

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
				recordId: ''
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
							className: 'form-control'
							onChange: @_updateLastName
							value: @state.lastName
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "Record ID"),
						R.input({
							className: 'form-control'
							onChange: @_updateRecordId
							value: @state.recordNumber
							placeholder: "(optional)"
						})
					)
					R.div({className: 'btn-toolbar'},
						R.button({
							className: 'btn btn-default'
							onClick: @_cancel							
						}, "Cancel")
						R.button({
							className: 'btn btn-primary'
							onClick: @_submit
							disabled: not @state.firstName or not @state.lastName
						}, "Create File")
					)
			)
		_cancel: ->
			@props.onCancel()
		_updateFirstName: (event) ->
			@setState {firstName: event.target.value}
		_updateMiddleName: (event) ->
			@setState {middleName: event.target.value}
		_updateLastName: (event) ->
			@setState {lastName: event.target.value}
		_updateRecordId: (event) ->
			@setState {recordId: event.target.value}
		_submit: ->


			first = @state.firstName
			middle = @state.middleName
			last = @state.lastName
			recordId = @state.recordId

			@setState {isLoading: true}

			clientFile = Imm.fromJS {
			  clientName: {first, middle, last}
			  recordId: recordId
			  plan: {
			    sections: []
			  }
			}
			
			global.ActiveSession.persist.clientFiles.create clientFile, (err, obj) =>
				@setState {isLoading: false}

				if err
					# TODO: Logic to check for pre-existing client file
					# if err instanceof Persist.Users.UserNameTakenError
					# 	Bootbox.alert "That user name is already taken."
					# 	return

					console.error err.stack
					Bootbox.alert "An error occurred while creating the account"
					return

				console.log("Client file created:", obj.get('id'))

				Bootbox.alert
					message: "New client file created for " + first + ' ' + last + '.'
					callback: =>
						@props.onSuccess(obj.get('id'))

	return CreateClientFileDialog

module.exports = {load}
