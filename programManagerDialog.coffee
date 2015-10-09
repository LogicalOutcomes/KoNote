# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0
Imm = require 'immutable'
Async = require 'async'	

Persist = require './persist'
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
	LayeredComponentMixin = require('./layeredComponentMixin').load(win)
	ExpandingTextArea = require('./expandingTextArea').load(win)
	{FaIcon, showWhen, stripMetadata} = require('./utils').load(win)

	ClientProgramsDialog = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin, LayeredComponentMixin]

		getInitialState: ->
			return {
				openDialogId: null
			}

		render: ->
			return Dialog({
				title: "#{Term 'Client'} #{Term 'Programs'}"
				onClose: @props.onCancel
			},
				R.div({className: 'clientProgramsDialog'},
					Spinner({
						isVisible: @state.mode in ['loading', 'working']
						isOverlay: true
					})					
					R.div({},
						R.div({className: 'btn-toolbar'},
							R.button({
								className: 'btn btn-primary'
								onClick: @_openCreateProgramDialog
							},
								FaIcon('plus')
								" New #{Term 'Program'}"
							)
						)
						if @props.programs.size is 0
							R.div({className: 'noData'}, "No #{Term 'programs'} exist yet.")
						else
							R.table({className: 'table table-striped'},
								R.tbody({},
									(@props.programs.map (program) =>
										R.tr({},
											R.td({className: 'nameCell'}, program.get('name'))
											R.td({className: 'descriptionCell'}, program.get('description'))
											R.td({className: 'buttonsCell'},
												R.div({className: 'btn-group'},
													R.button({
														className: 'btn btn-default'
														# onClick: @_openDialog 'manageClients'
													}, 
														"Manage #{Term 'Clients'}"
													)
													R.button({
														className: 'btn btn-warning'
														onClick: @_openEditProgramDialog.bind null, program
													},
														"Edit"
													)
												)
											)
										)
									)
								)
							)
						)
				)
			)

		renderLayer: ->
			switch @state.openDialogId
				when 'createProgram'
					return CreateProgramDialog({
						onClose: @_closeDialog
						onCancel: @_closeDialog
						onSuccess: @_closeDialog
					})
				when 'editProgram'
					return EditProgramDialog({
						onClose: @_closeDialog
						onCancel: @_closeDialog						
						onSuccess: @_closeDialog
						data: @state.editData
					})
				# when 'manageClients'
				# 	return ManageClientsDialog({
				# 		onClose: @_closeDialog
				# 		onCancel: @_closeDialog
				# 		onSuccess: ()
				# 	})
				when null
					return R.div()
				else
					throw new Error "Unknown dialog ID: #{JSON.stringify @state.openDialogId}"

		_openCreateProgramDialog: ->
			@setState {openDialogId: 'createProgram'}
		_openEditProgramDialog: (programData) ->
			@setState {
				editData: programData
				openDialogId: 'editProgram'
			}

		_closeDialog: (event) ->
			@setState {openDialogId: null}		

	CreateProgramDialog = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]
		getInitialState: ->
			return {
				name: ''
				description: ''
				isLoading: false
			}

		render: ->
			Dialog({
				title: "Create New #{Term 'Program'}"
				onClose: @props.onCancel
			}
				R.div({className: 'createProgramDialog'}
					Spinner({
						isVisible: @state.isLoading
						isOverlay: true
					})
					R.div({className: 'form-group'},
						R.label({}, "Name")
						R.input({
							className: 'form-control'
							value: @state.name
							onChange: @_updateName
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "Description")
						R.textarea({
							className: 'form-control'
							value: @state.description
							onChange: @_updateDescription
							rows: 3
						})
					)
					R.div({className: 'btn-toolbar'},
						R.button({
							className: 'btn btn-default'
							onClick: @props.onCancel
						}, "Cancel")
						R.button({
							className: 'btn btn-primary'
							disabled: not @state.name or not @state.description
							onClick: @_submit
						}, "Create #{Term 'Program'}")
					)
				)
			)

		_updateName: (event) ->
			@setState {name: event.target.value}
		_updateDescription: (event) ->
			@setState {description: event.target.value}

		_submit: (event) ->
			event.preventDefault()

			newProgram = Imm.Map({
				name: @state.name
				description: @state.description
			})

			# Create the new program, and close
			ActiveSession.persist.programs.create newProgram, (err, newProgram) =>
				if err
					CrashHandler.handle err
					return

				@props.onSuccess()

	EditProgramDialog = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]
		getInitialState: ->
			return {
				id: @props.data.get('id')
				name: @props.data.get('name')
				description: @props.data.get('description')
				isLoading: false
			}

		render: ->
			Dialog({
				title: "Editing #{Term 'Program'}"
				onClose: @props.onCancel
			}
				R.div({className: 'editProgramDialog'}
					R.div({className: 'form-group'},
						R.label({}, "Name")
						R.input({
							className: 'form-control'
							value: @state.name
							onChange: @_updateName
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "Description")
						R.textarea({
							className: 'form-control'
							value: @state.description
							onChange: @_updateDescription
							rows: 3
						})
					)
					R.div({className: 'btn-toolbar'},
						R.button({
							className: 'btn btn-default'
							onClick: @props.onCancel
						}, "Cancel")
						R.button({
							className: 'btn btn-primary'
							disabled: not @state.name or not @state.description or not @_hasChanges()
							onClick: @_submit
							type: 'submit'
						}, "Finished Editing")
					)
				)
			)
		_updateName: (event) ->
			@setState {name: event.target.value}
		_updateDescription: (event) ->
			@setState {description: event.target.value}

		_hasChanges: ->
			return not Imm.is @_compileProgramObject(), @props.data

		_compileProgramObject: ->
			return Imm.Map({
				id: @state.id
				name: @state.name
				description: @state.description
			})

		_submit: ->
			editedProgram = @_compileProgramObject()

			# Create new revision for program, and close
			ActiveSession.persist.programs.createRevision editedProgram, (err, updatedProgram) =>
				if err
					CrashHandler.handle.err
					return

				@props.onSuccess()

	return ClientProgramsDialog

module.exports = {load}