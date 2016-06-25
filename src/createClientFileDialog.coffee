# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# A dialog for allowing the user to create a new client file
Async = require 'async'

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
	ProgramBubbles = require('./programBubbles').load(win)
	ColorKeyBubble = require('./colorKeyBubble').load(win)

	{renderName, renderRecordId} = require('./utils').load(win)

	CreateClientFileDialog = React.createFactory React.createClass
		displayName: 'CreateClientFileDialog'
		mixins: [React.addons.PureRenderMixin]

		componentDidMount: ->
			@refs.firstNameField.focus()

		getInitialState: ->
			return {
				firstName: ''
				middleName: ''
				lastName: ''
				recordId: ''
				programIds: Imm.List()
				clientfileId: ''
			}

		render: ->
			Dialog({
				ref: 'dialog'
				title: "Create New #{Term 'Client File'}"
				onClose: @props.onClose
			},
				R.div({className: 'createClientFileDialog'},
					R.div({className: 'form-group'},
						R.label({}, "First Name"),
						R.input({
							ref: 'firstNameField'
							className: 'form-control'
							onChange: @_updateFirstName
							value: @state.firstName
							onKeyDown: @_onEnterKeyDown
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "Middle Name"),
						R.input({
							className: 'form-control'
							onChange: @_updateMiddleName
							value: @state.middleName
							placeholder: "(optional)"
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "Last Name"),
						R.input({
							className: 'form-control'
							onChange: @_updateLastName
							value: @state.lastName
							onKeyDown: @_onEnterKeyDown
						})
					)

					(unless @props.programs.isEmpty()
						R.div({className: 'form-group'},
							R.label({}, "Assign to #{Term 'Program'}(s)")
							R.div({id: 'programsContainer'},
								(@props.programs.map (program) =>
									isSelected = @state.programIds.contains(program.get('id'))
									R.button({
										className: 'btn btn-default programOptionButton'
										onClick:
											(if isSelected then @_removeFromPrograms else @_pushToPrograms)
											.bind null, program.get('id')
										key: program.get('id')
										value: program.get('id')
										},
										ColorKeyBubble({
											isSelected
											data: program
											key: program.get('id')
										})
										program.get('name')
									)
								)
							)
						)
					)

					(if Config.clientFileRecordId.isEnabled
						R.div({className: 'form-group'},
							R.label({}, Config.clientFileRecordId.label),
							R.input({
								className: 'form-control'
								onChange: @_updateRecordId
								value: @state.recordId
								placeholder: "(optional)"
								onKeyDown: @_onEnterKeyDown
							})
						)
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
						}, "Create #{Term 'Client File'}")
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

		_pushToPrograms: (programId) ->
			programIds = @state.programIds.push programId
			@setState {programIds}

		_removeFromPrograms: (programId) ->
			index = @state.programIds.indexOf(programId)
			programIds = @state.programIds.splice(index, 1)
			@setState {programIds}

		_onEnterKeyDown: (event) ->
			if event.which is 13 and @state.firstName and @state.lastName
				@_submit()

		_submit: ->
			@refs.dialog.setIsLoading(true)

			first = @state.firstName
			middle = @state.middleName
			last = @state.lastName
			recordId = @state.recordId

			clientFile = Imm.fromJS {
			  clientName: {first, middle, last}
			  recordId
			  plan: {
			    sections: []
			  }
			}

			clientFileHeaders = null
			newClientFileObj = null

			Async.series [
				(cb) =>
					# First pull the latest clientFile headers for uniqueness comparison
					ActiveSession.persist.clientFiles.list (err, result) =>
						if err
							cb err
							return

						clientFileHeaders = result

						# Enforce uniqueness of clientFileRecordId
						matchingClientRecordId = clientFileHeaders.find (clientFile) ->
							clientFile.get('recordId') and (clientFile.get('recordId') is recordId)

						if matchingClientRecordId
							@refs.dialog.setIsLoading(false) if @refs.dialog?

							Bootbox.alert """
								Sorry, #{renderRecordId recordId} is already in use by
								#{renderName matchingClientRecordId.get('clientName')}.
								Please try again with a unique #{Config.clientFileRecordId.label}.
							"""
							return

						# Warn if first & last name already used, but may continue
						matchingClientName = clientFileHeaders.find (clientFile) ->
							sameFirstName = clientFile.getIn(['clientName', 'first']).toLowerCase() is first.toLowerCase()
							sameLastName = clientFile.getIn(['clientName', 'last']).toLowerCase()  is last.toLowerCase()
							return sameFirstName and sameLastName

						if matchingClientName
							@refs.dialog.setIsLoading(false) if @refs.dialog?

							matchingClientRecordId = if Config.clientFileRecordId.isEnabled
								" #{renderRecordId matchingClientName.get('recordId')}"
							else
								""

							Bootbox.confirm """
								The name \"#{first} #{last} matches an existing #{Term 'client file'}
								in the database
								(#{renderName matchingClientName.get('clientName')}#{matchingClientRecordId}).
								Would you like to create this new #{Term 'client file'} anyway?
							""", (ok) ->
								if ok then cb() else return
						else
							cb()
				(cb) =>
					# Create the clientFile,
					global.ActiveSession.persist.clientFiles.create clientFile, (err, result) =>
						if err
							cb err
							return

						newClientFileObj = result
						cb()
				(cb) =>
					# Build the link objects
					clientFileProgramLinks = @state.programIds.map (programId) ->
						Imm.fromJS {
							clientFileId: newClientFileObj.get('id')
							status: 'enrolled'
							programId
						}

					# Build every link in list asyncronously, then cb
					Async.each clientFileProgramLinks.toArray(), (link, cb) ->
						global.ActiveSession.persist.clientFileProgramLinks.create link, cb
					, cb

			], (err) =>
				@refs.dialog.setIsLoading(false) if @refs.dialog?

				if err
					if err instanceof Persist.IOError
						console.error err
						Bootbox.alert """
							Please check your network connection and try again.
						"""
						return

					CrashHandler.handle err
					return

				# UI will be auto-updated with new file/links by page listeners
				@props.onSuccess()


	return CreateClientFileDialog

module.exports = {load}
