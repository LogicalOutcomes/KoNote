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
	Slider = require('./slider').load(win)
	LayeredComponentMixin = require('./layeredComponentMixin').load(win)
	ExpandingTextArea = require('./expandingTextArea').load(win)
	{FaIcon, showWhen, stripMetadata, renderName} = require('./utils').load(win)

	ProgramManagerDialog = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin, LayeredComponentMixin]

		getInitialState: ->
			return {
				openDialogId: null
				expandedMemberLists: Imm.List()
			}

		render: ->
			noData = @props.programs.size is 0

			return Dialog({
				title: "#{Term 'Client'} #{Term 'Programs'}"
				onClose: @props.onCancel
				containerClasses: ['noPadding'] unless noData
				disableBackgroundClick: true
			},
				R.div({className: 'programManagerDialog'},
					Spinner({
						isVisible: @state.mode in ['loading', 'working']
						isOverlay: true
					})
					(if noData
						# Fresh-run UI
						R.div({className: 'noData'}, 
							R.span({}, "No #{Term 'programs'} exist yet.")
							R.button({
								className: 'btn btn-primary btn-lg'
								onClick: @_openCreateProgramDialog
							},
								FaIcon('plus')
								" Create #{Term 'Program'}"
							)
						)
					else
						R.div({className: 'hasData'},
							R.div({className: 'options'},
								R.button({
									className: 'btn btn-primary'
									onClick: @_openCreateProgramDialog
								},
									FaIcon('plus')
									" Create #{Term 'Program'}"
								)
							)
							R.table({className: 'table table-striped'},
								R.tbody({},
									(@props.programs.map (program) =>
										isExpanded = @state.expandedMemberLists.includes program.get('id')

										R.tr({},
											R.td({},
												R.h4({
													className: 'programName'
													onClick: @_toggleExpandedView.bind null, program.get('id')
												},
													(if not isExpanded
														FaIcon('plus')
													else
														FaIcon('minus')
													)
													program.get 'name'
												)

												(if isExpanded
													R.div({},
														R.p({}, program.get 'description')
														R.span({className: 'clientName'}, 
															R.span({}, "ClientA")
															FaIcon('times', {
																onClick: @_removeClientFromProgram.bind null, 12345, program.get('id')
															})
														)
													)
												)
											)
											R.td({},
												R.div({className: 'btn-group'},
													R.button({
														className: 'btn btn-warning'
														onClick: @_openEditProgramDialog.bind null, program
													}, "Edit")
													R.button({
														className: 'btn btn-default'
														onClick: @_openManageClientsDialog.bind null, program
													},														
														Term 'Clients'
														R.span({className: 'badge'}, 0)
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
				when 'manageProgramClients'
					return ManageProgramClientsDialog({
						onClose: @_closeDialog
						onCancel: @_closeDialog						
						onSuccess: @_closeDialog
						data: @state.editData
					})
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
		_openManageClientsDialog: (program) ->
			@setState {				
				openDialogId: 'manageProgramClients'
				editData: {
					program
					clientFileHeaders: @props.clientFileHeaders
				}
			}

		_toggleExpandedView: (programId) ->
			# Toggling logic for list of open membership 
			if @state.expandedMemberLists.includes programId
				listIndex = @state.expandedMemberLists.indexOf programId
				expandedMemberLists = @state.expandedMemberLists.delete listIndex
			else
				expandedMemberLists = @state.expandedMemberLists.push programId

			@setState {expandedMemberLists}
		
		_removeClientFromProgram: (clientId, programId) ->
			Bootbox.confirm "Are you sure you want to remove clientId from program?", (confirmed) =>
				if confirmed
					Bootbox.alert "Ok, deleting..."

		_closeDialog: (event) ->
			@setState {openDialogId: null}		

	CreateProgramDialog = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]
		getInitialState: ->
			return {
				name: ''
				description: ''
				colorHuePercent: null
				isLoading: false
			}

		componentDidMount: ->
			@refs.programName.getDOMNode().focus()

		render: ->
			return Dialog({
				title: "Create New #{Term 'Program'}"
				onClose: @props.onCancel
				containerClasses: ['noPadding']
			},
				R.div({
					className: 'createProgramDialog'
					style: {
						background: if @state.colorHuePercent?
							"hsl(#{(@state.colorHuePercent / 100) * 360},100%,90%)"
					}
				},
					Spinner({
						isVisible: @state.isLoading
						isOverlay: true
					})
					R.div({className: 'form-group'},
						R.label({}, "#{Term 'Program'} Name")
						R.input({
							ref: 'programName'
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
					R.div({className: 'form-group'},
						R.label({}, "Choose a color key")
						Slider({
							isEnabled: true
							tooltip: false
							isRange: false
							minValue: 0
							maxValue: 100
							onSlide: @_updateColorHuePercent
						})
					)
					R.div({className: 'btn-toolbar'},
						R.button({
							className: 'btn btn-default'
							onClick: @props.onCancel
						}, "Cancel")
						R.button({
							className: 'btn btn-success'
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
		_updateColorHuePercent: (event) ->
			colorHuePercent = event.target.value
			console.log "Hue:", colorHuePercent
			@setState {colorHuePercent}

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
			return Dialog({
				title: "Editing #{Term 'Program'}"
				onClose: @props.onCancel
			},
				# Uses createProgramDialog stylesheet, own for overrides
				R.div({className: 'createProgramDialog editProgramDialog'}
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
							className: 'btn btn-success'
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

	ManageProgramClientsDialog = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]
		getInitialState: ->
			return {
				searchQuery: ''
				selectedClientIds: Imm.List()
			}

		componentDidMount: ->
			@refs.clientSearchBox.getDOMNode().focus()

		render: ->
			searchResults = @_getResultsList()

			return Dialog({
				title: "Manage #{Term 'Program'} #{Term 'Clients'}"
				onClose: @props.onClose
			},
				R.div({className: 'manageProgramClientsDialog'},
					R.div({className: 'clientPicker panel panel-default'},
						R.div({className: 'panel-heading'}
							R.label({}, "Search")
							R.input({
								className: 'form-control'
								placeholder: "by #{Term 'client'} name" + 
								(" or #{Config.clientFileRecordId.label}" if Config.clientFileRecordId?)
								onChange: @_updateSearchQuery
								ref: 'clientSearchBox'
							})
						)
						(if searchResults.isEmpty()
							R.div({className: 'panel-body noData'}, 
								"No #{Term 'client'} matches for \"#{@state.searchQuery}\""
							)
						else
							R.table({className: 'panel-body table'},
								R.thead({},
									R.tr({},
										R.td({}, Config.clientFileRecordId) if Config.clientFileRecordId?
										R.td({colspan: 2}, "#{Term 'Client'} Name")
									)
								)
								R.tbody({},
									(searchResults.map (result) =>
										clientId = result.get('id')
										recordId = result.get('recordId')

										R.tr({key: "result-" + clientId},
											if Config.clientFileRecordId?
												R.td({}, 
													(if recordId.length > 0
														recordId
													else
														R.div({className: 'noId'}, "n/a")
													)
												)
											R.td({}, renderName result.get('clientName'))
											R.td({},
												(if @state.selectedClientIds.includes clientId											
													R.button({
														className: 'btn btn-danger btn-sm'
														onClick: @_removeClientId.bind null, clientId
													},
														FaIcon('minus')
													)
												else
													R.button({
														className: 'btn btn-default btn-sm'
														onClick: @_addClientId.bind null, clientId
													},
														FaIcon('plus')
													)
												)
											)
										)
									)
								)
							)
						)
					)
					R.div({className: 'programClients panel panel-default'},
						R.div({className: 'panel-heading'}, 
							R.h3({className: 'panel-title'},
								if not @state.selectedClientIds.isEmpty()
									R.span({className: 'badge'}, @state.selectedClientIds.size)
								@props.data.program.get('name')
							)
						)
						(if @state.selectedClientIds.isEmpty()
							R.div({className: 'panel-body noData'},
								"This #{Term 'program'} has no members yet."
							)
						else
							R.table({className: 'panel-body table table-striped'}
								R.thead({},
									R.tr({},
										R.td({}, Config.clientFileRecordId) if Config.clientFileRecordId?
										R.td({colspan: 2}, "#{Term 'Client'} Name")
									)
								)
								R.tbody({},
									(@state.selectedClientIds.map (clientId) =>
										client = @_findClientById clientId
										recordId = client.get('recordId')

										R.tr({key: "selected-" + clientId},
											if Config.clientFileRecordId?
												R.td({}, 
													(if recordId.length > 0
														recordId
													else
														R.div({className: 'noId'}, "n/a")
													)
												)
											R.td({}, renderName client.get('clientName'))
											R.td({}, 
												R.button({
													className: 'btn btn-danger btn-sm'
													onClick: @_removeClientId.bind null, clientId
												},
													FaIcon('minus')
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

		_addClientId: (clientId) ->
			selectedClientIds = @state.selectedClientIds.push clientId
			@setState {selectedClientIds}
		_removeClientId: (clientId) ->
			listIndex = @state.selectedClientIds.indexOf clientId
			selectedClientIds = @state.selectedClientIds.delete listIndex
			@setState {selectedClientIds}
		_findClientById: (clientId) ->
			@props.data.clientFileHeaders.find (client) -> client.get('id') is clientId

		_updateSearchQuery: (event) ->
			@setState {searchQuery: event.target.value}

		_getResultsList: ->
			queryParts = Imm.fromJS(@state.searchQuery.split(' '))
			.map (p) -> p.toLowerCase()

			return @props.data.clientFileHeaders
			.filter (clientFile) ->
				firstName = clientFile.getIn(['clientName', 'first']).toLowerCase()
				middleName = clientFile.getIn(['clientName', 'middle']).toLowerCase()
				lastName = clientFile.getIn(['clientName', 'last']).toLowerCase()
				recordId = clientFile.getIn(['recordId']).toLowerCase()				

				return queryParts
				.every (part) ->
					return firstName.includes(part) or
						middleName.includes(part) or
						lastName.includes(part) or
						recordId.includes(part)

	return ProgramManagerDialog

module.exports = {load}