# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0
Imm = require 'immutable'
Async = require 'async'	
TinyColor = require 'tinycolor2'

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
			# noData = @props.programs.size is 0

			console.log "@props.programs", @props.programs

			return R.div({className: 'programManagerTab'},
				R.div({className: 'header'},
					R.h1({}, Term 'Programs')
				)
				R.div({className: 'main'},
					OrderableTable({
						data: Imm.List @props.programs
						rowStyle: (row) =>
							return {
								background: row.get('colorHex')
							}
						columns: Imm.List [
							{
								name: "Program Name"
								dataPath: ['name']
							}
							{
								name: "Description"
								dataPath: ['description']
							}
							{
								name: "Options"
								nameIsVisible: false
								buttons: [
									{
										className: 'btn btn-default'
										text: "Modify"
										dialog: EditProgramDialog
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
					})
				)
			)	

	CreateProgramDialog = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]
		getInitialState: ->
			return {
				name: ''
				description: ''
				colorHuePercent: 0
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
							maxValue: 99
							defaultValue: 0
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
			@setState {colorHuePercent}

		_submit: (event) ->
			event.preventDefault()

			hueDegrees = (@state.colorHuePercent / 100) * 360
			colorHex = TinyColor({
				h: hueDegrees
				s: 100
				l: 90
			}).toHexString()

			console.log "colorHex", colorHex

			newProgram = Imm.fromJS({
				name: @state.name
				description: @state.description
				colorHex
			})

			# Create the new program, and close
			ActiveSession.persist.programs.create newProgram, (err, newProgram) =>
				if err
					CrashHandler.handle err
					return

				console.log "Added new program:", newProgram
				@props.onSuccess()


	EditProgramDialog = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]
		getInitialState: ->
			return {
				id: @props.data.get('id')
				name: @props.data.get('name')
				description: @props.data.get('description')
				colorHuePercent: @_convertToHuePercent @props.data.get('colorHex')
				isLoading: false
			}		

		componentDidMount: ->
			@refs.programName.getDOMNode().focus()

		render: ->
			return Dialog({
				title: "Editing #{Term 'Program'}"
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
							maxValue: 99
							onSlide: @_updateColorHuePercent
							defaultValue: @state.colorHuePercent
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
						}, "Modify #{Term 'Program'}")
					)
				)
			)

		_updateName: (event) ->
			@setState {name: event.target.value}
		_updateDescription: (event) ->
			@setState {description: event.target.value}
		_updateColorHuePercent: (event) ->
			colorHuePercent = event.target.value
			@setState {colorHuePercent}

		_convertToHuePercent: (hex) ->
			hsl = TinyColor(hex).toHsl()
			huePercent = (hsl.h / 360) * 100
			return huePercent

		_submit: (event) ->
			event.preventDefault()

			hueDegrees = (@state.colorHuePercent / 100) * 360
			colorHex = TinyColor({
				h: hueDegrees
				s: 100
				l: 90
			}).toHexString()

			console.log "colorHex", colorHex

			editedProgram = Imm.fromJS({
				id: @props.data.get('id')
				name: @state.name
				description: @state.description
				colorHex
			})

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

	return ProgramManagerTab

module.exports = {load}