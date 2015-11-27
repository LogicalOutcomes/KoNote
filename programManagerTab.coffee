# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0
Imm = require 'immutable'
Async = require 'async'	
_ = require 'underscore'

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
	OrderableTable = require('./orderableTable').load(win)
	OpenDialogButton = require('./openDialogButton').load(win)
	ExpandingTextArea = require('./expandingTextArea').load(win)
	{FaIcon, showWhen, stripMetadata, renderName} = require('./utils').load(win)

	ProgramManagerTab = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				openDialogId: null
				expandedMemberLists: Imm.List()
			}

		render: ->
			# Inject number of clients into each program
			programs = @props.programs.map (program) ->
				newProgram = program.set 'numberClients', 999
				return newProgram

			return R.div({className: 'programManagerTab'},
				R.div({className: 'header'},
					R.h1({}, Term 'Programs')
				)
				R.div({className: 'main'},
					OrderableTable({
						tableData: programs
						sortBy: ['name']
						columns: [
							{
								name: "Color Key"
								nameIsVisible: false
								dataPath: ['colorKeyHex']								
								cellClass: 'colorKeyCell'
								valueStyle: (dataPoint) ->
									return {
										background: dataPoint.get('colorKeyHex')
									}
								hideValue: true
							}
							{
								name: "Program Name"
								dataPath: ['name']
								cellClass: 'nameCell'
							}
							{
								name: "Description"
								dataPath: ['description']
							}
							{
								name: Term 'Clients'
								cellClass: 'numberClientsCell'
								buttons: [{
									className: 'btn btn-default'
									dataPath: ['numberClients']
									icon: 'user'
									dialog: ManageProgramClientsDialog
									data:
										clientFileHeaders: @props.clientFileHeaders
										clientFileProgramLinks: @props.clientFileProgramLinks
								}]
							}
							{
								name: "Options"
								nameIsVisible: false
								cellClass: 'optionsCell'
								buttons: [
									{
										className: 'btn btn-warning'
										text: null
										icon: 'wrench'
										dialog: CreateProgramDialog
										data: 
											clientFileProgramLinks: @props.clientFileProgramLinks
									}
								]
							}
						]
					})
				)
				R.div({className: 'optionsMenu'},
					OpenDialogButton({
						className: 'btn btn-lg btn-primary'
						text: "New #{Term 'Program'} "
						icon: 'plus'
						dialog: CreateProgramDialog
						data: {
							clientFileHeaders: @props.clientFileHeaders
						}
					})
				)
			)	

	CreateProgramDialog = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				name: ''
				colorKeyHex: null
				description: ''
			}

		componentDidMount: ->
			@refs.programName.getDOMNode().focus()

			initColorPicker @refs.colorPicker.getDOMNode()

		render: ->
			return Dialog({
				title: "Create New #{Term 'Program'}"
				onClose: @props.onCancel
			},
				R.div({className: 'createProgramDialog'},
					R.div({className: 'form-group'},						
						R.label({}, "Name and Color Key")
						R.div({className: 'input-group'},
							R.input({
								className: 'form-control'
								ref: 'programName'
								value: @state.name
								onChange: @_updateName
								style:
									borderColor: @state.colorKeyHex
							})
							R.div({
								className: 'input-group-addon'
								id: 'colorPicker'
								ref: 'colorPicker'
								style:
									background: @state.colorKeyHex
									borderColor: @state.colorKeyHex
							},
								R.span({
									className: 'hasColor' if @state.colorKeyHex?
								},
									FaIcon 'eyedropper'
								)
							)
						)
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
							disabled: not @state.name or not @state.description
							onClick: @_createProgram
						}, 
							"Create #{Term 'Program'}"
						)
					)
				)
			)

		_updateName: (event) ->
			@setState {name: event.target.value}

		_updateDescription: (event) ->
			@setState {description: event.target.value}

		_buildProgramObject: ->
			return Imm.fromJS({
				name: @state.name
				description: @state.description
				colorKeyHex: @state.colorKeyHex
			})

		_createProgram: (event) ->
			event.preventDefault()

			newProgram = @_buildProgramObject()

			# Create the new program, and close
			ActiveSession.persist.programs.create newProgram, (err, newProgram) =>
				if err
					CrashHandler.handle err
					return

				console.log "Added new program:", newProgram
				@props.onSuccess()

	ModifyProgramDialog = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				name: @props.rowData.name
				colorKeyHex: @props.rowData.colorHexKey
				description: @props.rowData.description
			}

		componentDidMount: ->
			@refs.programName.getDOMNode().focus()

			initColorPicker @refs.colorPicker.getDOMNode()

		render: ->
			return Dialog({
				title: "Create New #{Term 'Program'}"
				onClose: @props.onCancel
			},
				R.div({className: 'createProgramDialog'},
					R.div({className: 'form-group'},						
						R.label({}, "Name and Color Key")
						R.div({className: 'input-group'},
							R.input({
								className: 'form-control'
								ref: 'programName'
								value: @state.name
								onChange: @_updateName
								style:
									borderColor: @state.colorKeyHex
							})
							R.div({
								className: 'input-group-addon'
								id: 'colorPicker'
								ref: 'colorPicker'
								style:
									background: @state.colorKeyHex
									borderColor: @state.colorKeyHex
							},
								R.span({
									className: 'hasColor' if @state.colorKeyHex?
								},
									FaIcon 'eyedropper'
								)
							)
						)
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
							disabled: not @state.name or not @state.description
							onClick: @_createProgram
						}, 
							"Create #{Term 'Program'}"
						)
					)
				)
			)

		_updateName: (event) ->
			@setState {name: event.target.value}

		_updateDescription: (event) ->
			@setState {description: event.target.value}

		_buildProgramObject: ->
			return Imm.fromJS({
				name: @state.name
				description: @state.description
				colorKeyHex: @state.colorKeyHex
			})

		_createProgram: (event) ->
			event.preventDefault()

			newProgram = @_buildProgramObject()

			# Create the new program, and close
			ActiveSession.persist.programs.create newProgram, (err, newProgram) =>
				if err
					CrashHandler.handle err
					return

				@props.onSuccess()

	initColorPicker = (colorPicker) ->
		# Set up color picker
		$(colorPicker).spectrum(
			showPalette: true
			palette: [
				['YellowGreen', 'Tan', 'Violet']
				['Teal', 'Sienna', 'RebeccaPurple']
				['Maroon', 'Cyan', 'LightSlateGray']
			]
			move: (color) =>
				colorKeyHex = color.toHexString()
				@setState {colorKeyHex}
		)

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
				title: "Managing #{Term 'Clients'} in \"#{@props.rowData.get('name')}\""
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
								@props.rowData.get('name')
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
				R.div({className: 'btn-toolbar'},
					R.button({
						className: 'btn btn-default'
						onClick: @props.onCancel
					},
						"Cancel"
					)
					R.button({
						className: 'btn btn-success btn-large'
						# onClick: @_submit
					}, 
						"Finished"
						FaIcon('check')
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
			@props.clientFileHeaders.find (client) -> client.get('id') is clientId

		_updateSearchQuery: (event) ->
			@setState {searchQuery: event.target.value}

		_getResultsList: ->
			queryParts = Imm.fromJS(@state.searchQuery.split(' '))
			.map (p) -> p.toLowerCase()

			return @props.clientFileHeaders
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

	return ProgramManagerTab

module.exports = {load}