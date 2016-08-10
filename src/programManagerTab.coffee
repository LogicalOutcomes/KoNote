# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

Async = require 'async'
Imm = require 'immutable'
_ = require 'underscore'

Persist = require './persist'
Config = require './config'
Term = require './term'
{ProgramColors} = require './colors'


load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	{PropTypes} = React
	R = React.DOM

	# TODO: Refactor to single require
	{BootstrapTable, TableHeaderColumn} = win.ReactBootstrapTable
	BootstrapTable = React.createFactory BootstrapTable
	TableHeaderColumn = React.createFactory TableHeaderColumn

	CrashHandler = require('./crashHandler').load(win)
	Dialog = require('./dialog').load(win)
	Spinner = require('./spinner').load(win)
	OrderableTable = require('./orderableTable').load(win)
	OpenDialogLink = require('./openDialogLink').load(win)
	ExpandingTextArea = require('./expandingTextArea').load(win)
	ColorKeyBubble = require('./colorKeyBubble').load(win)
	ColorKeySelection = require('./colorKeySelection').load(win)
	DialogLayer = require('./dialogLayer').load(win)

	{FaIcon, showWhen, stripMetadata, renderName} = require('./utils').load(win)


	ProgramManagerTab = React.createFactory React.createClass
		displayName: 'ProgramManagerTab'
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

			hasInactivePrograms = @props.clientFileProgramLinks.filter (link) ->
				link.get('status') is "enrolled"

			return R.div({className: 'programManagerTab'},
				R.div({className: 'header'},
					R.h1({}, Term 'Programs')
				)
				R.div({className: 'main'},
					R.div({className: 'responsiveTable'},
						DialogLayer({
							ref: 'dialogLayer'
							programs
							clientFileProgramLinks: @props.clientFileProgramLinks
						}
							BootstrapTable({
								data: programs.toJS()
								keyField: 'id'
								bordered: false
								options: {
									defaultSortName: 'name'
									defaultSortOrder: 'asc'
									onRowClick: ({id}) =>
										@refs.dialogLayer.open ModifyProgramDialog, {programId: id}
								}
							},
								TableHeaderColumn({
									dataField: 'colorKeyHex'
									dataFormat: (colorKeyHex) -> ColorKeyBubble({colorKeyHex})
									width: '100px'
								})
								TableHeaderColumn({
									dataField: 'name'
								}, "#{Term 'Program'} Name")
								TableHeaderColumn({
									dataField: 'description'
								}, "Description")
								TableHeaderColumn({
									dataField: 'numberClients'
									headerAlign: 'center'
									dataAlign: 'center'
								}, "# #{Term 'Clients'}")
							)
						)
					)
				)
				(if isAdmin
					R.div({className: 'optionsMenu'},
						OpenDialogLink({
							className: 'btn btn-lg btn-primary'
							dialog: CreateProgramDialog
							data: {
								clientFileHeaders: @props.clientFileHeaders
								programs
							}
						},
							FaIcon('plus')
							' '
							"New #{Term 'Program'} "
						)
					)
				)
			)

	CreateProgramDialog = React.createFactory React.createClass
		displayName: 'CreateProgramDialog'
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
				ref: 'dialog'
				title: "Create New #{Term 'Program'}"
				onClose: @props.onCancel
			},
				R.div({className: 'createProgramDialog'},
					R.div({className: 'form-group'},
						R.label({}, "Name")
						R.input({
							className: 'form-control'
							ref: 'programName'
							placeholder: "Specify #{Term 'program'} name"
							value: @state.name
							onChange: @_updateName
							style:
								borderColor: @state.colorKeyHex
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "Color Key")
						ColorKeySelection({
							colors: ProgramColors
							data: @props.data.programs
							selectedColorKeyHex: @state.colorKeyHex
							onSelect: @_updateColorKeyHex
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "Description")
						R.textarea({
							className: 'form-control'
							placeholder: "Describe the #{Term 'program'}"
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
							onClick: @_submit
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

		_updateColorKeyHex: (colorKeyHex) ->
			@setState {colorKeyHex}

		_buildProgramObject: ->
			return Imm.fromJS({
				name: @state.name
				description: @state.description
				colorKeyHex: @state.colorKeyHex
			})

		_submit: (event) ->
			event.preventDefault()

			newProgram = @_buildProgramObject()
			@_createProgram(newProgram)

		_createProgram: (newProgram) ->
			@refs.dialog.setIsLoading(true)

			# Create the new program, and close
			ActiveSession.persist.programs.create newProgram, (err, newProgram) =>
				@refs.dialog.setIsLoading(false) if @refs.dialog?

				if err
					CrashHandler.handle err
					return

				@props.onSuccess()


	ModifyProgramDialog = React.createFactory React.createClass
		displayName: 'ModifyProgramDialog'
		mixins: [React.addons.PureRenderMixin]

		propTypes: {
			programId: PropTypes.string.isRequired
		}

		getInitialState: ->
			return @_getProgram().toJS()

		componentDidMount: ->
			@refs.programName.focus()

		render: ->
			return Dialog({
				ref: 'dialog'
				title: "Modifying #{Term 'Program'}"
				onClose: @props.onCancel
			},
				R.div({className: 'createProgramDialog'},
					R.div({className: 'form-group'},
						R.label({}, "Name")
						R.input({
							className: 'form-control'
							ref: 'programName'
							placeholder: "Specify #{Term 'program'} name"
							value: @state.name
							onChange: @_updateName
							style:
								borderColor: @state.colorKeyHex
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "Colour Key")
						ColorKeySelection({
							colors: ProgramColors
							data: @props.programs
							selectedColorKeyHex: @state.colorKeyHex
							onSelect: @_updateColorKeyHex
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "Description")
						R.textarea({
							className: 'form-control'
							placeholder: "Describe the #{Term 'program'}"
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
								not @state.name or not @state.description or not @state.colorKeyHex
							) or not @_hasChanges()
							onClick: @_submit
						},
							"Finished"
						)
					)
				)
			)

		_updateName: (event) ->
			@setState {name: event.target.value}

		_updateDescription: (event) ->
			@setState {description: event.target.value}

		_updateColorKeyHex: (colorKeyHex) ->
			@setState {colorKeyHex}

		_getProgram: ->
			@props.programs.find (program) =>
				program.get('id') is @props.programId

		_buildModifiedProgramObject: ->
			return Imm.fromJS({
				id: @props.programId
				name: @state.name
				description: @state.description
				colorKeyHex: @state.colorKeyHex
			})

		_hasChanges: ->
			originalProgramObject = @_getProgram()
			modifiedProgramObject = @_buildModifiedProgramObject()
			return not Imm.is originalProgramObject, modifiedProgramObject

		_submit: (event) ->
			event.preventDefault()

			modifiedProgram = @_buildModifiedProgramObject()

			@refs.dialog.setIsLoading(true)

			# Update program revision, and close
			ActiveSession.persist.programs.createRevision modifiedProgram, (err, modifiedProgram) =>
				@refs.dialog.setIsLoading(false) if @refs.dialog?

				if err
					CrashHandler.handle err
					return

				@props.onSuccess()


	ManageProgramClientsDialog = React.createFactory React.createClass
		displayName: 'ManageProgramClientsDialog'
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
				ref: 'dialog'
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

			@refs.dialog.setIsLoading(true)

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
				@refs.dialog.setIsLoading(false) if @refs.dialog?

				if err
					CrashHandler.handle err
					return

				@props.onSuccess()


	return ProgramManagerTab

module.exports = {load}
