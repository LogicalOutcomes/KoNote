# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# A dialog for allowing the user to rename a client file

Persist = require './persist'
Imm = require 'immutable'
Config = require './config'
Term = require './term'


load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	CrashHandler = require('./crashHandler').load(win)
	Dialog = require('./dialog').load(win)
	Spinner = require('./spinner').load(win)


	RenameClientFileDialog = React.createFactory React.createClass
		displayName: 'RenameClientFileDialog'
		mixins: [React.addons.PureRenderMixin]

		componentDidMount: ->
			@refs.firstNameField.focus()

		getInitialState: ->
			return {
				firstName: @props.clientFile.getIn(['clientName', 'first'])
				middleName: @props.clientFile.getIn(['clientName', 'middle'])
				lastName: @props.clientFile.getIn(['clientName', 'last'])
				recordId: @props.clientFile.get('recordId')
				status: @props.clientFile.get('status')
			}

		render: ->
			Dialog({
				ref: 'dialog'
				title: "Edit #{Term 'Client File'}"
				onClose: @props.onClose
			},
				R.div({className: 'renameClientFileDialog'},
					R.div({className: 'form-group'},
						R.label({}, "First name"),
						R.input({
							ref: 'firstNameField'
							className: 'form-control'
							onChange: @_updateFirstName
							value: @state.firstName
							onKeyDown: @_onEnterKeyDown
							maxLength: 32
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "Middle name"),
						R.input({
							className: 'form-control'
							onChange: @_updateMiddleName
							value: @state.middleName
							placeholder: "(optional)"
							maxLength: 32
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "Last name"),
						R.input({
							className: 'form-control'
							onChange: @_updateLastName
							value: @state.lastName
							onKeyDown: @_onEnterKeyDown
							maxLength: 32
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "Client File Status"),
						R.div({className: 'btn-toolbar'},
							R.button({
								className:
									if @state.status is 'active'
										'btn btn-success'
									else 'btn btn-default'
								onClick: @_updateStatus
								value: 'active'

								},
							"Active"
							)
							R.button({
								className:
									if @state.status is 'inactive'
										'btn btn-warning'
									else 'btn btn-default'
								onClick: @_updateStatus
								value: 'inactive'

								},
							"Inactive"
							)
							R.button({
								className:
									if @state.status is 'discharged'
										'btn btn-danger'
									else 'btn btn-default'
								onClick: @_updateStatus
								value: 'discharged'

								},
							"Discharged"
							)
						)
					)
					if Config.clientFileRecordId.isEnabled
						R.div({className: 'form-group'},
							R.label({}, Config.clientFileRecordId.label),
							R.input({
								className: 'form-control'
								onChange: @_updateRecordId
								value: @state.recordId
								placeholder: "(optional)"
								onKeyDown: @_onEnterKeyDown
								maxLength: 32
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
						}, "Save changes")
					)
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

		_updateStatus: (event) ->
			@setState {status: event.target.value}

		_onEnterKeyDown: (event) ->
			if event.which is 13 and @state.firstName and @state.lastName
				@_submit()

		_submit: ->
			@refs.dialog.setIsLoading true

			updatedClientFile = @props.clientFile
			.setIn(['clientName', 'first'], @state.firstName)
			.setIn(['clientName', 'middle'], @state.middleName)
			.setIn(['clientName', 'last'], @state.lastName)
			.set('recordId', @state.recordId)
			.set('status', @state.status)

			global.ActiveSession.persist.clientFiles.createRevision updatedClientFile, (err, obj) =>
				@refs.dialog.setIsLoading(false) if @refs.dialog?

				if err
					if err instanceof Persist.IOError
						console.error err
						console.error err.stack
						Bootbox.alert """
							Please check your network connection and try again.
						"""
						return

					CrashHandler.handle err
					return

				@props.onSuccess()

	return RenameClientFileDialog

module.exports = {load}
