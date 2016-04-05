# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

Async = require 'async'	
Imm = require 'immutable'
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
	OpenDialogLink = require('./openDialogLink').load(win)
	ExpandingTextArea = require('./expandingTextArea').load(win)
	ColorKeyBubble = require('./colorKeyBubble').load(win)

	{FaIcon, showWhen, stripMetadata, renderName} = require('./utils').load(win)

	ProgramManagerTab = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		render: ->
			# Inject numberClients into each program
			programs = @props.programs.map (program) =>
				programId = program.get('id')
				numberClients = @props.clientFileProgramLinks
				.filter (link) -> link.get('programId') is programId and link.get('status') is "enrolled"
				.size

				newProgram = program.set 'numberClients', numberClients
				return newProgram

			isAdmin = global.ActiveSession.isAdmin()

			return R.div({className: 'programManagerTab'},
				R.div({className: 'header'},
					R.h1({}, Term 'Programs')
				)
				R.div({className: 'main'},
					OrderableTable({
						tableData: programs
						noMatchesMessage: "No #{Term 'programs'} exist yet"
						sortByData: ['name']
						columns: [
							{
								name: "Color Key"
								nameIsVisible: false
								dataPath: ['colorKeyHex']								
								cellClass: 'colorKeyCell'
								value: (dataPoint) ->
									ColorKeyBubble({colorKeyHex: dataPoint.get('colorKeyHex')})
							}
							{
								name: "Program Name"
								dataPath: ['name']
								cellClass: 'nameCell'
							}
							{
								name: "Description"
								dataPath: ['description']
								value: (dataPoint) ->
									description = dataPoint.get('description')

									if description.length > 60
										return description.substr(0, 59) + ' . . .'
									else
										return description
							}
							{
								name: Term 'Clients'
								cellClass: 'numberClientsCell'
								dataPath: ['numberClients']
								hideValue: true
								buttons: [{
									className: 'btn btn-default'
									dataPath: ['numberClients']
									icon: 'users'
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
								isDisabled: not isAdmin
								buttons: [
									{
										className: 'btn btn-warning'
										text: null
										icon: 'wrench'
										dialog: ModifyProgramDialog
										data: 
											clientFileProgramLinks: @props.clientFileProgramLinks
									}
								]
							}
						]
					})
				)
				if isAdmin
					R.div({className: 'optionsMenu'},
						OpenDialogLink({
							className: 'btn btn-lg btn-primary'
							dialog: CreateProgramDialog
							data: {
								clientFileHeaders: @props.clientFileHeaders
							}
						},
							FaIcon('plus')
							' '
							"New #{Term 'Program'} "
						)
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
			@refs.programName.focus()


		render: ->
			return Dialog({
				title: "Create New #{Term 'Program'}"
				onClose: @props.onCancel
			},


				R.div({className: 'createProgramDialog'},
					R.div({className: 'form-group'},						
						R.label({}, "Name")
						R.div({className: 'input-group'},
							R.input({
								className: 'form-control'
								ref: 'programName'
								value: @state.name
								onChange: @_updateName
							})
						)
					)
					R.div({className: 'form-group'},
						R.label({}, "Color")
						ColorKeyBubble({colorKeyHex: "blue"})

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
							disabled: not @state.name or not @state.description or not @state.colorKeyHex
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

	ModifyProgramDialog = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				name: @props.rowData.get('name')
				colorKeyHex: @props.rowData.get('colorKeyHex')
				description: @props.rowData.get('description')
			}

		componentDidMount: ->
			@refs.programName.focus()
			@_initColorPicker @refs.colorPicker

		render: ->
			return Dialog({
				title: "Modifying #{Term 'Program'}"
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
							disabled: (
								@state.name or not @state.description or not @state.colorKeyHex
							) and @_hasChanges()
							onClick: @_modifyProgram
						}, 
							"Finished"
						)
					)
				)
			)

		_initColorPicker: (colorPicker) ->
			# Set up color picker
			$(colorPicker).spectrum(
				showPalette: true
				color: @state.colorKeyHex
				palette: [
					['YellowGreen', 'Tan', 'Violet']
					['Teal', 'Sienna', 'RebeccaPurple']
					['Maroon', 'Cyan', 'LightSlateGray']
				]
				move: (color) =>
					colorKeyHex = color.toHexString()
					@setState {colorKeyHex}
			)

		_updateName: (event) ->
			@setState {name: event.target.value}

		_updateDescription: (event) ->
			@setState {description: event.target.value}

		_buildModifiedProgramObject: ->
			return Imm.fromJS({
				id: @props.rowData.get('id')
				name: @state.name
				description: @state.description
				colorKeyHex: @state.colorKeyHex
			})

		_buildOriginalProgramObject: ->
			# Explicitly remove numberClients for diff-ing,
			# since it's not a part of the original DB object
			return @props.rowData.remove('numberClients')

		_hasChanges: ->
			originalProgramObject = @_buildOriginalProgramObject()
			modifiedProgramObject = @_buildModifiedProgramObject()
			return Imm.is originalProgramObject, modifiedProgramObject

		_modifyProgram: (event) ->
			event.preventDefault()

			modifiedProgram = @_buildModifiedProgramObject()

			# Update program revision, and close
			ActiveSession.persist.programs.createRevision modifiedProgram, (err, modifiedProgram) =>
				if err
					CrashHandler.handle err
					return

				@props.onSuccess()


	ManageProgramClientsDialog = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				searchQuery: ''
				clientFileProgramLinks: @_originalLinks()
			}

		_originalLinks: ->
			return @props.clientFileProgramLinks
			.filter (link) => link.get('programId') is @props.rowData.get('id')
			.map (link) => return Imm.fromJS {
				clientFileId: link.get('clientFileId')
				status: link.get('status')
			}

		componentDidMount: ->
			@refs.clientSearchBox.focus()

		render: ->
			searchResults = @_getResultsList()

			enrolledLinks = @state.clientFileProgramLinks.filter (link) ->
				link.get('status') is "enrolled"

			return Dialog({
				title: "Managing #{Term 'Clients'} in \"#{@props.rowData.get('name')}\""
				onClose: @props.onClose
			},
				R.div({className: 'manageProgramClientsDialog'},
					R.div({className: 'programClients'},
						R.div({className: 'panel-heading'},
							R.h3({className: 'panel-title'},
								if not enrolledLinks.isEmpty()
									R.span({className: 'badge'}, enrolledLinks.size)
								"Current Members"
							)
						)
						(if enrolledLinks.isEmpty()
							R.div({className: 'panel-body noData'},
								"This #{Term 'program'} has no members yet."
							)
						else
							R.table({className: 'panel-body table table-striped'}
								R.thead({},
									R.tr({},
										R.td({}, Config.clientFileRecordId.label) if Config.clientFileRecordId?
										R.td({colSpan: 2}, "#{Term 'Client'} Name")
									)
								)
								R.tbody({},
									(enrolledLinks.map (link) =>
										clientFileId = link.get('clientFileId')
										client = @_findClientById clientFileId
										recordId = client.get('recordId')

										R.tr({key: clientFileId},
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
													onClick: @_unenrollClient.bind null, clientFileId
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
										R.td({}, Config.clientFileRecordId.label) if Config.clientFileRecordId?
										R.td({colSpan: 2}, "#{Term 'Client'} Name")
									)
								)
								R.tbody({},
									(searchResults.map (result) =>
										clientFileId = result.get('id')
										recordId = result.get('recordId')

										clientIsEnrolled = enrolledLinks.find (link) ->													
											link.get('clientFileId') is clientFileId

										R.tr({key: clientFileId},
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
												R.button({
													className: 'btn btn-success btn-sm'
													style: {
														visibility: 'hidden' if clientIsEnrolled?
													}
													onClick: @_enrollClient.bind null, clientFileId
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
				R.div({className: 'btn-toolbar pull-right'},
					R.button({
						className: 'btn btn-default'
						onClick: @props.onCancel
					},
						"Cancel"
					)
					R.button({
						className: 'btn btn-success btn-large'
						onClick: @_submit
					}, 
						"Finished "
						FaIcon('check')
					)
				)
			)

		_enrollClient: (clientFileId) ->
			newLink = Imm.fromJS {
				clientFileId
				status: "enrolled"
			}

			existingLink = @state.clientFileProgramLinks.find (link) ->
				link.get('clientFileId') is clientFileId

			if existingLink?
				if existingLink.get('status') isnt "enrolled"
					# Link exists, but isn't enrolled. Let's enroll him/her/...it
					linkIndex = @state.clientFileProgramLinks.indexOf existingLink
					clientFileProgramLinks = @state.clientFileProgramLinks.set(linkIndex, newLink)
					@setState {clientFileProgramLinks}
				else
					# Client is already enrolled. This shouldn't happen.
					console.warn "Tried to enroll already-enrolled clientFileId:", clientFileId
			else
				# Link doesn't exist, so just push in the new one
				clientFileProgramLinks = @state.clientFileProgramLinks.push newLink
				@setState {clientFileProgramLinks}



		_unenrollClient: (clientFileId) ->
			newLink = Imm.fromJS {
				clientFileId
				status: "unenrolled"
			}

			existingLink = @state.clientFileProgramLinks.find (link) ->
				link.get('clientFileId') is clientFileId

			if existingLink?
				if existingLink.get('status') is "enrolled"
					# Link exists, but is enrolled. Let's unenroll him/her/...it
					linkIndex = @state.clientFileProgramLinks.indexOf existingLink
					clientFileProgramLinks = @state.clientFileProgramLinks.set(linkIndex, newLink)
					@setState {clientFileProgramLinks}
				else
					# Client is already unenrolled. This shouldn't happen.
					console.warn "Tried to UNenroll already-UNenrolled clientFileId:", clientFileId
			else
				# Link doesn't exist, so just push in the new one
				clientFileProgramLinks = @state.clientFileProgramLinks.push newLink
				@setState {clientFileProgramLinks}


		_findClientById: (clientFileId) ->
			@props.clientFileHeaders.find (client) -> client.get('id') is clientFileId

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


		_submit: (event) ->
			event.preventDefault()

			programId = @props.rowData.get('id')

			programLinks = @props.clientFileProgramLinks.filter (link) ->
				link.get('programId') is programId

			Async.map @state.clientFileProgramLinks.toArray(), (newLink, cb) =>

				existingLink = programLinks.find (originalLink) =>
					originalLink.get('clientFileId') is newLink.get('clientFileId')

				if existingLink?
					# Pull out the full link object from props
					linkIndex = programLinks.indexOf existingLink
					clientFileProgramLink = programLinks.get linkIndex
					# Update its status
					revisedLink = clientFileProgramLink.set 'status', newLink.get('status')

					# Create the revision on DB
					ActiveSession.persist.clientFileProgramLinks.createRevision revisedLink, (err, updatedLink) ->
						if err
							cb err
							return

						cb()

				else
					# Build our brand new link object
					newLink = Imm.fromJS(newLink)
					.set 'programId', programId

					# Create new link object on DB
					ActiveSession.persist.clientFileProgramLinks.create newLink, (err, createdLink) ->
						if err
							cb err
							return

						cb()

			, (err) =>
				if err
					CrashHandler.handle err
					return

				@props.onSuccess()


	return ProgramManagerTab

module.exports = {load}
