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
				mode: 'loading' # loading, ready, or working
				openDialogId: null

				clientFileHeaders: null
				programs: Imm.List()
			}

		componentWillMount: ->
			clientFileHeaders = null
			programHeaders = null
			programs = null

			Async.series [
				(cb) =>
					ActiveSession.persist.clientFiles.list (err, result) =>
						if err
							cb err
							return

						clientFileHeaders = result
						console.log "clientFileHeaders", clientFileHeaders.toJS()
						cb()
				(cb) =>
					ActiveSession.persist.programs.list (err, result) =>
						if err
							cb err
							return

						programHeaders = result
						console.log "programHeaders", programHeaders.toJS()
						cb()
				(cb) =>
					Async.map programHeaders.toArray(), (programHeader, cb) =>
						progId = programHeader.get('id')
						ActiveSession.persist.programs.readLatestRevisions progId, 1, cb
					, (err, results) =>
							if err
								cb err
								return

							programs = Imm.List(results).map (program) -> stripMetadata program.get(0)
							cb()
			], (err) =>
				if err
					if err instanceof Persist.IOError
						Bootbox.alert "Please check your network connection and try again.", =>
							@props.onCancel()
						return

					CrashHandler.handle err
					return

				@setState {
					clientFileHeaders
					programs
					mode: 'ready'
				}

		render: ->
			# if @state.mode is 'loading'
			# 	return R.div({})
			# else
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
						if @state.programs.size is 0
							R.div({className: 'noData'}, "No #{Term 'programs'} exist yet.")
						else
							R.table({className: 'table table-striped'},
								R.tbody({},
									(@state.programs.map (program) =>
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
						onSuccess: (newProgram) =>		
						# Update programs with new one and close dialog					
							programs = @state.programs.push newProgram							
							@setState {programs}, @_closeDialog
					})
				when 'editProgram'
					console.log "Editing program!"
					return EditProgramDialog({
						onClose: @_closeDialog
						onCancel: @_closeDialog
						data: @state.editData
						onSuccess: (updatedProgram) =>
						# Update program at list index and close dialog
							index = @state.programs.indexOf @state.editData
							programs = @state.programs.set index, updatedProgram
							@setState {programs}, @_closeDialog
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
			console.log "Triggered"
			@setState {
				editData: programData
				openDialogId: 'editProgram'
			}

		_closeDialog: (event) ->
			event.preventDefault()			
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
					R.form({},
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
								type: 'submit'
							}, "Create #{Term 'Program'}")
						)
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

			# Create the new program, and trigger success
			ActiveSession.persist.programs.create newProgram, (err, newProgram) =>
				if err
					CrashHandler.handle err
					return

				@props.onSuccess(newProgram)

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

		_submit: (event) ->
			console.log "EVENT:", event
			event.preventDefault()
			console.log "Event", event

			editedProgram = @_compileProgramObject()

			# Make new revision for this program ID
			ActiveSession.persist.programs.createRevision editedProgram, (err, updatedProgram) =>
				if err
					CrashHandler.handle.err
					return

				# Deliver updated program back to main dialog
				@props.onSuccess updatedProgram

	return ClientProgramsDialog

module.exports = {load}
