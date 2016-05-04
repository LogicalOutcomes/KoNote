# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# A dialog for allowing the user to create a new client file

Persist = require './persist'
Imm = require 'immutable'
Config = require './config'
Term = require './term'

load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	B = require('./utils/reactBootstrap').load(win, 'DropdownButton', 'MenuItem')

	CrashHandler = require('./crashHandler').load(win)
	Dialog = require('./dialog').load(win)
	Spinner = require('./spinner').load(win)
	ProgramBubbles = require('./programBubbles').load(win)
	ColorKeyBubble = require('./colorKeyBubble').load(win)

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
						R.label({}, "First name"),
						R.input({
							ref: 'firstNameField'
							className: 'form-control'
							onChange: @_updateFirstName
							value: @state.firstName
							onKeyDown: @_onEnterKeyDown
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
							onKeyDown: @_onEnterKeyDown
						})
					)
				
					R.div({className: 'form-group'},
						R.label({}, "Select #{Term 'Program'}(s)")
						R.div({className: 'programsContainer'},
						
						(@props.programs.map (program) =>

							R.button({
								className: 'btn btn-default'
								onClick: 
									if program.get('id') in @props.programIds
										@_removeFromPrograms.bind null, program.get('id')
									else @_pushToPrograms.bind null, program.get('id')	
								key: program.get('id')
								value: program.get('id')
								},
								ColorKeyBubble({
									data: program
									key: program.get('id')
								})
								program.get('name')
							)
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
						}, "Create #{Term 'File'}")
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
		_pushToPrograms: (event) ->
			tempArray = @state.programIds
			tempArray = tempArray.push event
			@setState {programIds: tempArray}

		_removeFromPrograms: (event) ->
			tempArray = @state.programIds
			index = tempArray.indexOf(event)
			tempArray.splice(index, 1)

			@setState {programIds: tempArray}

		_onEnterKeyDown: (event) ->
			if event.which is 13 and @state.firstName and @state.lastName
				@_submit()
		_submit: ->
			first = @state.firstName
			middle = @state.middleName
			last = @state.lastName
			recordId = @state.recordId

			@refs.dialog.setIsLoading(true)

			clientFile = Imm.fromJS {
			  clientName: {first, middle, last}
			  recordId: recordId
			  plan: {
			    sections: []
			  }
			}

			global.ActiveSession.persist.clientFiles.create clientFile, (err, obj) =>
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

				@props.onSuccess(obj.get('id'))

				console.log "obj.getID >>>>", obj.get('id')
				
				# @setState {clientFileId: obj.get('id')}


				# creating client file program links  (now in cb of create clientFile)
				console.log "state of programIds before creating links >>>>>>", @state.programIds.toJS()

				programIds = @state.programIds
				console.log "final programIds array to be looped >>>>>> ", programIds.toJS()

				programIds.forEach (programId) ->
					console.log "programId in loop>>>>>", programId
					link = Imm.fromJS {
						clientFileId: obj.get('id')
						status: 'enrolled'
						programId
					}

					global.ActiveSession.persist.clientFileProgramLinks.create link, (err, link) =>
						if err
							if err instanceof Persist.IOError
								console.error err
								Bootbox.alert """
									Please check your network connection and try again.
								"""
								return

							CrashHandler.handle err
							return
						console.log "created LINK >>>>>", link.toJS()


	return CreateClientFileDialog

module.exports = {load}
