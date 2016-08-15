# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

Async = require 'async'
Imm = require 'immutable'
_ = require 'underscore'
ImmPropTypes = require 'react-immutable-proptypes'

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

	{Tabs, Tab} = require('./utils/reactBootstrap').load(win, 'Tabs', 'Tab')

	CrashHandler = require('./crashHandler').load(win)
	Dialog = require('./dialog').load(win)
	Spinner = require('./spinner').load(win)
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
							clientFileHeaders: @props.clientFileHeaders
						}
							BootstrapTable({
								data: programs.toJS()
								keyField: 'id'
								bordered: false
								options: {
									defaultSortName: 'name'
									defaultSortOrder: 'asc'
									onRowClick: @_openProgramManagerDialog
								}
							},
								TableHeaderColumn({
									dataField: 'colorKeyHex'
									columnClassName: 'colorKeyColumn'
									dataFormat: (colorKeyHex) -> ColorKeyBubble({colorKeyHex})
								})
								TableHeaderColumn({
									dataField: 'name'
									columnClassName: 'nameColumn'
									dataSort: true
								}, "#{Term 'Program'} Name")
								TableHeaderColumn({
									dataField: 'description'
									columnClassName: 'descriptionColumn'
								}, "Description")
								TableHeaderColumn({
									dataField: 'numberClients'
									dataSort: true
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

		_openProgramManagerDialog: ({id}) ->
			@refs.dialogLayer.open ManageProgramDialog, {programId: id}

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
			# Create the new program, and close
			ActiveSession.persist.programs.create newProgram, (err, newProgram) =>

				if err
					CrashHandler.handle err
					return

				@props.onSuccess()


	ManageProgramDialog = React.createFactory React.createClass
		displayName: 'ManageProgramDialog'
		mixins: [React.addons.PureRenderMixin]

		propTypes: {
			programId: PropTypes.string.isRequired
			clientFileProgramLinks: ImmPropTypes.list
			clientFileHeaders: ImmPropTypes.list
		}

		getInitialState: -> {
			# Admin will most frequently want to manage clients,
			# so this is the default view
			view: 'manageClients'
		}

		render: ->
			program = @props.programs.find (program) =>
				program.get('id') is @props.programId

			return Dialog({
				ref: 'dialog'
				title: "Manage #{Term 'Program'}"
				onClose: @props.onClose
			},
				R.div({className: 'manageProgramDialog'},
					Tabs({
						activeKey: @state.view
						onSelect: @_changeView
					}
						Tab({
							title: R.span({},
								ColorKeyBubble({colorKeyHex: program.get('colorKeyHex')})
								' '
								program.get('name')
							)
							eventKey: 'name'
							disabled: true
						})
						Tab({
							title: "#{Term 'Clients'}"
							eventKey: 'manageClients'
						},
							ManageProgramClientsView({
								program
								clientFileHeaders: @props.clientFileHeaders
								clientFileProgramLinks: @props.clientFileProgramLinks
								onSuccess: @props.onSuccess
							})
						)
						Tab({
							title: "Modify Details"
							eventKey: 'modifyProgram'
						},
							ModifyProgramView({
								program
								programs: @props.programs
								onSuccess: @props.onSuccess
							})
						)
					)
				)
			)

		_changeView: (view) ->
			@setState {view}


	ModifyProgramView = React.createFactory React.createClass
		displayName: 'ModifyProgramView'
		mixins: [React.addons.PureRenderMixin]

		propTypes: {
			program: ImmPropTypes.map
			programs: ImmPropTypes.list
		}

		getInitialState: ->
			return @props.program.toJS()

		componentDidMount: ->
			@refs.programName.focus()

		render: ->
			R.div({className: 'createProgramDialog'},
				R.div({className: 'innerContainer'},
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

		_buildModifiedProgramObject: ->
			return Imm.fromJS({
				id: @props.program.get('id')
				name: @state.name
				description: @state.description
				colorKeyHex: @state.colorKeyHex
			})

		_hasChanges: ->
			originalProgramObject = @props.program
			modifiedProgramObject = @_buildModifiedProgramObject()
			return not Imm.is originalProgramObject, modifiedProgramObject

		_submit: (event) ->
			event.preventDefault()

			modifiedProgram = @_buildModifiedProgramObject()

			# Update program revision, and close
			ActiveSession.persist.programs.createRevision modifiedProgram, (err, modifiedProgram) =>
				if err
					CrashHandler.handle err
					return

				@props.onSuccess()


	ManageProgramClientsView = React.createFactory React.createClass
		displayName: 'ManageProgramClientsView'
		mixins: [React.addons.PureRenderMixin]

		propTypes: {
			program: ImmPropTypes.map
			clientFileHeaders: ImmPropTypes.list
			clientFileProgramLinks: ImmPropTypes.list
		}

		getInitialState: ->
			return {
				searchQuery: ''
				clientFileProgramLinks: @_originalLinks()
			}

		componentDidMount: ->
			@refs.clientSearchBox.focus()

		render: ->
			enrolledLinks = @state.clientFileProgramLinks.filter (link) ->
				link.get('status') is "enrolled"

			# Filter out enrolled links from search results
			searchResults = @_getResultsList().filter (clientFile) =>
				clientFileId = clientFile.get('id')
				return not enrolledLinks.some (link) ->
					link.get('clientFileId') is clientFileId

			hasChanges = @_hasChanges()


			return R.div({className: 'manageProgramClientsView'},
				R.div({className: 'innerContainer'},
					R.div({className: 'programClientsContainer'},
						R.div({className: 'programClients'},
							R.div({className: 'panel-heading'},
								R.h3({className: 'panel-title'},
									(if not enrolledLinks.isEmpty()
										R.span({className: 'badge'},
											enrolledLinks.size
										)
									)
									"Enrolled #{Term 'Clients'}"
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
														className: 'btn btn-danger btn-xs'
														onClick: @_unenrollClient.bind null, link
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
					R.div({className: 'clientPickerContainer'},
						R.div({className: 'clientPicker'},
							R.div({className: 'panel panel-default'},
								R.div({className: 'panel-heading'}
									R.input({
										className: 'form-control'
										placeholder: "Search by #{Term 'client'} name" +
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
									R.div({className: 'panel-body searchResults'},
										R.table({className: 'table'},
											R.thead({},
												R.tr({},
													R.td({}, Config.clientFileRecordId.label) if Config.clientFileRecordId?
													R.td({}, "#{Term 'Client'} Name")
												)
											)
											R.tbody({},
												(searchResults.map (result) =>
													clientFileId = result.get('id')
													recordId = result.get('recordId')

													R.tr({
														key: clientFileId
														onClick: @_enrollClient.bind null, clientFileId
													},
														if Config.clientFileRecordId?
															R.td({},
																(if recordId.length > 0
																	recordId
																else
																	R.div({className: 'noId'}, "n/a")
																)
															)
														R.td({}, renderName result.get('clientName'))
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
				R.div({className: 'btn-toolbar pull-right saveBar'},
					R.button({
						className: 'btn btn-default'
						onClick: @props.onCancel
					},
						"Cancel"
					)
					R.button({
						className: 'btn btn-success btn-large'
						onClick: @_submit
						disabled: hasChanges
					},
						"Save "
						FaIcon('check')
					)
				)
			)

		_originalLinks: ->
			return @props.clientFileProgramLinks.filter (link) =>
				link.get('programId') is @props.program.get('id')

		_hasChanges: ->
			Imm.is @state.clientFileProgramLinks, @_originalLinks()

		_enrollClient: (clientFileId) ->
			newLink = Imm.fromJS {
				clientFileId
				status: "enrolled"
			}

			# Link already exists in state
			existingLink = @state.clientFileProgramLinks.find (link) ->
				link.get('clientFileId') is clientFileId

			# Link already exists in DB
			savedLink = @_originalLinks().find (link) ->
				link.get('clientFileId') is clientFileId

			# Use pre-existing DB link as template if exists
			if savedLink?
				newLink = savedLink.set 'status', "enrolled"

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

		_unenrollClient: (clientFileProgramLink) ->
			if clientFileProgramLink.get('status') isnt "enrolled"
				# Client is already unenrolled. This shouldn't happen.
				console.warn "Tried to UNenroll already-UNenrolled clientFileId:", clientFileId
				return

			linkIndex = @state.clientFileProgramLinks.indexOf clientFileProgramLink

			# Does link already have an ID / exist in the DB?
			linkId = clientFileProgramLink.get('id')
			isSavedLink = linkId?

			clientFileProgramLinks = if isSavedLink or existingLink?
				# Link exists, but is enrolled. Let's unenroll him/her
				@state.clientFileProgramLinks.set(linkIndex, clientFileProgramLink.set('status', "unenrolled"))
			else
				# Link has never been saved, so axe it completely
				@state.clientFileProgramLinks.remove linkIndex

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

			programId = @props.program.get('id')

			programLinks = @props.clientFileProgramLinks.filter (link) ->
				link.get('programId') is programId

			Async.map @state.clientFileProgramLinks.toArray(), (newLink, cb) =>
				if newLink.has('id')
					# Revise existing link, which will have an ID already
					ActiveSession.persist.clientFileProgramLinks.createRevision newLink, cb
				else
					newLink = newLink.set 'programId', programId
					ActiveSession.persist.clientFileProgramLinks.create newLink, cb

			, (err) =>
				if err
					CrashHandler.handle err
					return

				@props.onSuccess()


	return ProgramManagerTab

module.exports = {load}
