# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Node libs
Imm = require 'immutable'
ImmPropTypes = require 'react-immutable-proptypes'
Async = require 'async'
_ = require 'underscore'

Config = require './config'
Term = require './term'
Persist = require './persist'

load = (win) ->
	# Window libs
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	{PropTypes} = React
	ReactDOM = win.ReactDOM
	R = React.DOM

	# TODO: Refactor to single require
	{BootstrapTable, TableHeaderColumn} = win.ReactBootstrapTable
	BootstrapTable = React.createFactory BootstrapTable
	TableHeaderColumn = React.createFactory TableHeaderColumn

	Gui = win.require 'nw.gui'
	Window = Gui.Window.get()

	MainMenu = require('./mainMenu').load(win)
	BrandWidget = require('./brandWidget').load(win)
	OpenDialogLink = require('./openDialogLink').load(win)
	ProgramBubbles = require('./programBubbles').load(win)

	ManagerLayer = require('./managerLayer').load(win)
	CreateClientFileDialog = require('./createClientFileDialog').load(win)

	CrashHandler = require('./crashHandler').load(win)
	{FaIcon, openWindow, renderName, showWhen, stripMetadata} = require('./utils').load(win)

	ClientSelectionPage = React.createFactory React.createClass
		displayName: 'ClientSelectionPage'
		getInitialState: ->
			return {
				status: 'init'
				loadingFile: false
				clientFileHeaders: Imm.List()
				programs: Imm.List()
				userProgramOverride: null
				userProgramLinks: Imm.List()
				clientFileProgramLinks: Imm.List()
			}

		init: ->
			@props.setWindowTitle """
				#{Config.productName} (#{global.ActiveSession.userName})
			"""
			@_loadData()

		deinit: (cb=(->)) ->
			# Nothing to deinit
			cb()

		suggestClose: ->
			@props.closeWindow()

		render: ->
			unless @state.status is 'ready' then return R.div({})

			userProgram = @_getUserProgram()

			return ClientSelectionPageUi {
				openClientFile: @_openClientFile
				status: @state.status
				clientFileHeaders: @state.clientFileHeaders
				clientFileProgramLinks: @state.clientFileProgramLinks
				programs: @state.programs
				userProgram
				userProgramLinks: @state.userProgramLinks
				metricDefinitions: @state.metricDefinitions
			}

		_getUserProgram: ->
			# Use the userProgramOverride if exists
			if @state.userProgramOverride?
				return @state.userProgramOverride
			else
				# Find assigned userProgramLink
				currentUserProgramLink = @state.userProgramLinks.find (link) ->
					link.get('userName') is global.ActiveSession.userName and link.get('status') is 'assigned'

				if currentUserProgramLink?
					return @state.programs.find (program) ->
						program.get('id') is currentUserProgramLink.get('programId')
				else
					return null

		_openClientFile: (clientFileId) ->
			appWindows = chrome.app.window.getAll()
			# skip if no client files open
			if appWindows.length > 2
				clientName = ''
				ActiveSession.persist.clientFiles.readLatestRevisions clientFileId, 1, (err, revisions) =>
					if err
						# fail silently, let user retry
						return
					clientFile = stripMetadata revisions.get(0)
					clientName = renderName clientFile.get('clientName')
					clientFileOpen = false
					appWindows.forEach (appWindow) ->
						winTitle = nw.Window.get(appWindow.contentWindow).title
						if winTitle.includes(clientName)
							# already open, focus
							clientFileOpen = true
							nw.Window.get(appWindow.contentWindow).focus()
							return
					if clientFileOpen is false
						openWindow {
							page: 'clientFile'
							clientFileId
						}
			else
				openWindow {page: 'clientFile', clientFileId}, (clientFileWindow) =>
						# prevent window from closing before its ready
						clientFileWindow.on 'close', =>
							clientFileWindow = null

		_setStatus: (status) ->
			@setState {status}

		_loadData: ->
			clientFileHeaders = null
			programHeaders = null
			programs = null
			programsById = null
			userProgramLinks = null
			clientFileProgramLinkHeaders = null
			clientFileProgramLinks = null

			Async.parallel [
				(cb) =>
					ActiveSession.persist.clientFiles.list (err, result) =>
						if err
							cb err
							return

						clientFileHeaders = result
						cb()
				(cb) =>
					# TODO: Lazy load this
					Async.series [
						(cb) =>
							ActiveSession.persist.programs.list (err, result) =>
								if err
									cb err
									return

								programHeaders = result
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

								programsById = programs
								.map (program) -> [program.get('id'), program]
								.fromEntrySeq().toMap()

								cb()
						(cb) =>
							ActiveSession.persist.userProgramLinks.list (err, result) ->
								if err
									cb err
									return

								userProgramLinks = result.map (link) -> stripMetadata(link)

								cb()
					], cb
				(cb) =>
					# TODO: Lazy load this
					Async.series [
						(cb) =>
							ActiveSession.persist.clientFileProgramLinks.list (err, result) =>
								if err
									cb err
									return
								clientFileProgramLinkHeaders = result
								cb()
						(cb) =>
							Async.map clientFileProgramLinkHeaders.toArray(), (linkHeader, cb) =>
								linkId = linkHeader.get('id')

								ActiveSession.persist.clientFileProgramLinks.readLatestRevisions linkId, 1, cb
							, (err, results) =>
								if err
									cb err
									return

								clientFileProgramLinks = Imm.List(results).map (link) -> stripMetadata link.get(0)
								cb()
					], cb
			], (err) =>
				if err
					if err instanceof Persist.IOError
						console.error err
						console.error err.stack
						@setState {loadErrorType: 'io-error'}
						return

					CrashHandler.handle err
					return

				# Load in data
				@setState {
					status: 'ready'
					programs
					programsById
					userProgramLinks
					clientFileHeaders
					clientFileProgramLinks
				}

		getPageListeners: ->

			return {
				# Custom listener for overriding userProgram in ActiveSession
				'override:userProgram': (userProgram) =>
					if userProgram?
						console.log "Overriding userProgram to:", userProgram.toJS()

					global.ActiveSession.programId = if userProgram? then userProgram.get('id') else null
					@setState {userProgramOverride: userProgram}

				'create:userProgramLink createRevision:userProgramLink': (userProgramLink) =>
					isForCurrentUser = userProgramLink.get('userName') is global.ActiveSession.userName

					if isForCurrentUser
						if userProgramLink.get('status') is 'assigned'
							# Trigger override userProgram for current user
							userProgram = @state.programsById.get userProgramLink.get('programId')
							global.ActiveSession.persist.eventBus.trigger 'override:userProgram', userProgram
						else
							global.ActiveSession.persist.eventBus.trigger 'override:userProgram', null

					# Does a revision of the link already exist?
					existingLink = @state.userProgramLinks.find (link) -> link.get('id') is userProgramLink.get('id')

					if existingLink?
						# Overwrite existing link in state
						linkIndex = @state.userProgramLinks.indexOf existingLink
						userProgramLinks = @state.userProgramLinks.set linkIndex, userProgramLink
					else
						userProgramLinks = @state.userProgramLinks.push userProgramLink

					@setState {userProgramLinks}

				'create:clientFile': (newFile) =>
					clientFileHeaders = @state.clientFileHeaders.push newFile
					@setState {clientFileHeaders}

				'createRevision:clientFile': (newRev) =>
					clientFileId = newRev.get('id')
					existingClientFileHeader = @state.clientFileHeaders
					.find (clientFileHeader) -> clientFileHeader.get('id') is newRev.get('id')

					@setState (state) ->
						if existingClientFileHeader?
							clientFileIndex = state.clientFileHeaders.indexOf existingClientFileHeader
							clientFileHeaders = state.clientFileHeaders.set clientFileIndex, newRev
						else
							# clientFileHeaders = state.clientFileHeaders.push newRev
							return
						return {clientFileHeaders}

				'create:program createRevision:program': (newRev) =>
					programId = newRev.get('id')
					# Updating or creating program?
					existingProgram = @state.programs
					.find (program) -> program.get('id') is programId

					@setState (state) ->
						if existingProgram?
							programIndex = state.programs.indexOf existingProgram
							programs = state.programs.set programIndex, newRev
						else
							programs = state.programs.push newRev

						return {programs}

				'create:clientFileProgramLink createRevision:clientFileProgramLink': (newRev) =>
					linkId = newRev.get('id')
					# Updating or creating link?
					existingLink = @state.clientFileProgramLinks
					.find (link) -> link.get('id') is linkId

					@setState (state) ->
						if existingLink?
							linkIndex = state.clientFileProgramLinks.indexOf existingLink
							clientFileProgramLinks = state.clientFileProgramLinks.set linkIndex, newRev
						else
							clientFileProgramLinks = state.clientFileProgramLinks.push newRev

						return {clientFileProgramLinks}

			}



	ClientSelectionPageUi = React.createFactory React.createClass
		displayName: 'ClientSelectionPageUi'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				isSmallHeaderSet: false
				menuIsOpen: false
				menuIconIsOpen: true
				managerLayer: null

				queryText: ''
			}

		componentDidMount: ->
			# Fire 'loaded' event for loginPage to hide itself
			global.ActiveSession.persist.eventBus.trigger 'clientSelectionPage:loaded'
			@_attachKeyBindings()

		render: ->
			isAdmin = global.ActiveSession.isAdmin()
			smallHeader = @state.queryText.length > 0 or @state.isSmallHeaderSet

			return R.div({
				id: 'clientSelectionPage'
				className: 'animated fadeIn'
			},
				R.a({
					id: 'expandMenuButton'
					className: [
						'animated fadeIn'
						'menuIsOpen animated fadeInRight' if @state.menuIsOpen
					].join ' '
					onClick: =>
						@_toggleUserMenu()
						@refs.searchBox.focus() if @refs.searchBox? and @state.menuIsOpen
				},
					if @state.menuIsOpen
							FaIcon('times', {className:'animated fadeOutRight' unless @state.menuIconIsOpen})
					else
						"Menu"
				)
				R.div({
					id: 'mainContainer'
					style:
						width: if @state.menuIsOpen then '80%' else '100%'
				},
					(if @state.managerLayer?
						ManagerLayer({
							name: @state.managerLayer
							clientFileHeaders: @props.clientFileHeaders
							programs: @props.programs
							userProgramLinks: @props.userProgramLinks
							clientFileProgramLinks: @props.clientFileProgramLinks
							menuIsOpen: @state.menuIsOpen
						})
					)
					R.div({
						id: 'main'
						onClick: =>
							@_toggleUserMenu() if @state.menuIsOpen
							@refs.searchBox.focus() if @refs.searchBox?
					},
						R.header({
							className: [
								if smallHeader then 'small' else ''
							].join ' '
						},
							R.div({className: 'logoContainer'},
								R.img({src: Config.logoCustomerLg})
								R.div({
									className: 'subtitle'
									style: {color: Config.logoSubtitleColor}
								},
									Config.logoSubtitle
								)
							)
							R.div({className: 'searchBoxContainer'},
								noData = @props.clientFileHeaders.isEmpty()

								R.div({className: 'input-group'}
									unless noData
										OpenDialogLink({
											className: 'input-group-btn'
											ref: 'openCreateClientSmall'
											dialog: CreateClientFileDialog
											programs: @props.programs
										},
											R.button({
												className: 'btn btn-default'
												title: "Add new Client File"
											},
												R.span({className: 'text-success'}, FaIcon('plus'))
											)
										)

									R.input({
										className: 'searchBox form-control'
										ref: 'searchBox'
										type: 'text'
										autoFocus: true
										disabled: noData
										placeholder:
											unless noData
												"Search for a #{Term 'client'}'s profile..."
											else
												"No #{Term 'client files'} to search yet..."
										onChange: @_updateQueryText
										value: @state.queryText
									})

									R.span({className: 'input-group-btn'},
										(unless noData
											R.button({
												className: 'btn btn-default'
												onClick: @_showAll
											}, "Show All")
										else
											OpenDialogLink({
												className: 'btn btn-success'
												dialog: CreateClientFileDialog
												programs: @props.programs
											},
												"New #{Term 'Client File'} "
												FaIcon('folder-open')
											)
										)
									)
								)
							)
						)
						R.div({
							className: [
								'smallHeaderLogo'
								if smallHeader then 'show' else 'hidden'
							].join ' '
						},
							R.img({
								src: Config.logoCustomerLg
								onClick: @_home
							})
						)
						ClientTableWrapper({
							ref: 'clientTable'
							queryText: @state.queryText
							clientFileHeaders: @props.clientFileHeaders
							clientFileProgramLinks: @props.clientFileProgramLinks
							programs: @props.programs
							onRowClick: @_onResultSelection
						})
					)
				)

				(if @state.menuIsOpen
					MainMenu({
						ref: 'userMenu'
						className: 'menuIsOpen animated fadeInRight'
						isAdmin
						programs: @props.programs
						userProgram: @props.userProgram
						managerLayer: @state.managerLayer
						isSmallHeaderSet: @state.isSmallHeaderSet

						updateManagerLayer: @_updateManagerLayer
					})
				)
			)

		_attachKeyBindings: ->
			# Key-bindings for searchBox
			$(@refs.searchBox).on 'keydown', (event) =>
				# Don't need to see this unless in full search view
				return if not @state.isSmallHeaderSet

				switch event.which
					when 40 # Down arrow
						event.preventDefault()
						@refs.clientTable.shiftActiveIndex(1)
					when 38 # Up arrow
						event.preventDefault()
						@refs.clientTable.shiftActiveIndex(-1)
					when 27 # Esc
						@refs.clientTable.clearActiveIndex()
					when 13 # Enter
						$active = $('.activeIndex')
						return unless $active.length
						$active[0].click()
						return false

		_updateManagerLayer: (managerLayer) ->
			if managerLayer is null
				@setState {isSmallHeaderSet: true, queryText: '', managerLayer}
				return
			@setState {managerLayer}

		_toggleUserMenu: ->
			if @state.menuIsOpen
				mainMenuNode = ReactDOM.findDOMNode(@refs.userMenu)
				$(mainMenuNode).addClass('slideOutRight')

				# @setState {managerLayer: null}
				@setState {menuIconIsOpen: false}

				setTimeout(=>
					@setState {menuIsOpen: false}
				, 400)
			else
				@setState {menuIsOpen: true}
				@setState {menuIconIsOpen: true}

		_updateQueryText: (event) ->
			@setState {queryText: event.target.value}

			if event.target.value.length > 0
				@setState {isSmallHeaderSet: true}

		_showAll: ->
			@setState {isSmallHeaderSet: true, queryText: ''}

		_home: ->
			@setState {isSmallHeaderSet: false, queryText: ''}

		_onResultSelection: (clientFileId) ->
			@props.openClientFile(clientFileId)


	ClientTableWrapper = React.createFactory React.createClass
		displayName: 'ClientTableWrapper'

		propTypes: {
			queryText: PropTypes.string.isRequired

			clientFileHeaders: ImmPropTypes.list.isRequired
			clientFileProgramLinks: ImmPropTypes.list.isRequired
			programs: ImmPropTypes.list.isRequired

			onRowClick: PropTypes.func.isRequired
		}

		getInitialState: -> {
			displayInactive: null
		}

		render: ->
			queryResults = @_filterResults()

			# Add in all program objects this clientFile's a member of
			tableData = queryResults.map (clientFile) =>
				clientFileId = clientFile.get('id')

				programMemberships = @props.clientFileProgramLinks
				.filter (link) =>
					link.get('clientFileId') is clientFileId and link.get('status') is "enrolled"
				.map (link) =>
					@props.programs.find (program) -> program.get('id') is link.get('programId')

				givenNames = clientFile.getIn(['clientName', 'first'])
				middleName = clientFile.getIn(['clientName', 'middle'])
				if middleName then givenNames += ", #{middleName}"

				return clientFile
				.set('programs', programMemberships)
				.set('givenNames', givenNames) # Flatten names for columns
				.set('lastName', clientFile.getIn(['clientName', 'last']))

			# Get inactive clientFile results for filter display
			inactiveClientFiles = tableData.filter (clientFile) ->
				clientFile.get('status') isnt 'active'

			# Filter out inactive clientFile results by default
			if not @state.displayInactive
				tableData = tableData.filter (clientFile) ->
					clientFile.get('status') is 'active'

			# Are ANY clientFiles inactive?
			hasInactiveFiles = @props.clientFileHeaders.some (clientFile) ->
				clientFile.get('status') and (clientFile.get('status') isnt 'active')


			return R.div({className: 'clientTableWrapper'},
				# TODO: Component for multiple kinds of filters/toggles
				(if hasInactiveFiles
					R.div({id: 'filterSelectionContainer'}
						R.span({id: 'toggleDeactivated'},
							R.div({className: "checkbox"},
								R.label({}
									R.input({
										onChange: @_toggleInactive
										type: 'checkbox'
										checked: @state.displayInactive
									})
									"Show inactive (#{inactiveClientFiles.size})",
								)
							)
						)
					)
				)
				ClientTable({
					ref: 'clientTable'
					data: tableData
					queryText: @props.queryText
					hasProgramLinks: not @props.clientFileProgramLinks.isEmpty()
					hasInactiveFiles
					displayInactive: @state.displayInactive

					onRowClick: @props.onRowClick
				})
			)

		shiftActiveIndex: (modifier) -> @refs.clientTable.shiftActiveIndex(modifier)
		clearActiveIndex: -> @refs.clientTable.clearActiveIndex()

		_toggleInactive: ->
			@setState {displayInactive: not @state.displayInactive}

		_filterResults: ->
			if @props.queryText.trim().length is 0
				return @props.clientFileHeaders

			# Split into query parts
			queryParts = Imm.fromJS(@props.queryText.split(' ')).map (p) -> p.toLowerCase()

			# Calculate query results
			queryResults = @props.clientFileHeaders
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

			return queryResults


	ClientTable = React.createFactory React.createClass
		displayName: 'ClientTable'

		propTypes: {
			queryText: PropTypes.string.isRequired
			data: ImmPropTypes.list.isRequired
			hasProgramLinks: PropTypes.bool.isRequired
			hasInactiveFiles: PropTypes.bool.isRequired

			onRowClick: PropTypes.func.isRequired
		}

		getInitialState: -> {
			activeIndex: null
		}

		render: ->
			return R.div({className: 'responsiveTable'},
				BootstrapTable({
					data: @props.data.toJS()
					keyField: 'id'
					bordered: false
					options: {
						onRowClick: ({id}) => @props.onRowClick(id)
						noDataText: "No #{Term 'client files'} matching \"#{@props.queryText}\""
						defaultSortName: 'lastName'
						defaultSortOrder: 'asc'
					}
					trClassName: (row, index) => [
						'clientRow'
						'activeIndex' if index is @state.activeIndex
						'inactive' unless row.status is 'active'
					].join ' '
				},
					TableHeaderColumn({
						dataField: 'programs'
						dataFormat: (programs) ->
							return null unless programs
							ProgramBubbles({programs: Imm.fromJS(programs)})
						width: '150px'
					})
					TableHeaderColumn({
						dataField: 'lastName'
						dataSort: true
					}, "Last Name")
					TableHeaderColumn({
						dataField: 'givenNames'
						dataSort: true
					}, "Given Names")
					TableHeaderColumn({
						dataField: 'recordId'
						dataSort: true
						className: 'recordIdColumn'
						columnClassName: 'recordIdColumn'
						headerAlign: 'right'
						dataAlign: 'right'
						hidden: not Config.clientFileRecordId.isEnabled
					}, Config.clientFileRecordId.label)
					TableHeaderColumn({
						dataField: 'status'
						dataSort: true
						headerAlign: 'right'
						dataAlign: 'right'
						hidden: not @props.displayInactive
					}, "Status")
				)
			)

		shiftActiveIndex: (modifier) ->
			if @state.activeIndex is null
				activeIndex = 0
				@setState {activeIndex}
				return

			activeIndex = @state.activeIndex + modifier

			numberClientRows = @props.data.size

			if activeIndex < 0
				activeIndex = numberClientRows - 1
			else if activeIndex > (numberClientRows - 1)
				activeIndex = 0

			@setState {activeIndex}

		clearActiveIndex: -> @setState {activeIndex: null}


	return ClientSelectionPage

module.exports = {load}