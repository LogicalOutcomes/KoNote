# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0


Imm = require 'immutable'
Async = require 'async'

Config = require './config'
Term = require './term'
Persist = require './persist'


load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	ReactDOM = win.ReactDOM
	R = React.DOM

	# TODO: Refactor to single require
	{BootstrapTable, TableHeaderColumn} = win.ReactBootstrapTable
	BootstrapTable = React.createFactory BootstrapTable
	TableHeaderColumn = React.createFactory TableHeaderColumn

	MainMenu = require('./mainMenu').load(win)
	OpenDialogLink = require('./openDialogLink').load(win)
	ProgramBubbles = require('./programBubbles').load(win)
	ManagerLayer = require('./managerLayer').load(win)
	CreateClientFileDialog = require('./createClientFileDialog').load(win)
	CrashHandler = require('./crashHandler').load(win)
	{FaIcon, openWindow, renderName, stripMetadata, objectsAsIdMap} = require('./utils').load(win)


	ClientSelectionPage = React.createFactory React.createClass
		displayName: 'ClientSelectionPage'
		getInitialState: ->
			return {
				status: 'init'
				loadingFile: false
				clientFileHeaders: null
				metricsById: null
				programsById: null
				userProgramId: null
				userProgramLinks: Imm.List()
				clientFileProgramLinks: null
				displayAllPrograms: false
			}

		init: ->
			@props.setWindowTitle """
				#{Config.productName} (#{global.ActiveSession.userName})
			"""
			@_loadInitialData()

		deinit: (cb=(->)) ->
			# Nothing to deinit
			cb()

		suggestClose: ->
			nw.App.closeAllWindows()
			@props.closeWindow()

		render: ->
			unless @state.status is 'ready'
				return null

			userProgram = @_getUserProgram()
			isAdmin = global.ActiveSession.isAdmin()

			# For regular users, we filter out clientFiles that
			# and don't match the user's assigned program
			clientFileHeaders = if userProgram? and not @state.displayAllPrograms
				@state.clientFileHeaders.filter (clientFile) =>
					clientFileId = clientFile.get('id')

					@state.clientFileProgramLinks.some (link) =>
						link.get('clientFileId') is clientFileId and
						link.get('programId') is @state.userProgramId and
						link.get('status') is 'enrolled'
			else
				@state.clientFileHeaders


			return ClientSelectionPageUi {
				openClientFile: @_openClientFile
				clientFileHeaders
				clientFileProgramLinks: @state.clientFileProgramLinks
				programsById: @state.programsById
				userProgram
				userProgramLinks: @state.userProgramLinks
				metricsById: @state.metricsById
				displayAllPrograms: @state.displayAllPrograms
				toggleAllPrograms: @_toggleAllPrograms
			}

		_toggleAllPrograms: ->
			@setState {displayAllPrograms: not @state.displayAllPrograms}

		_getUserProgram: ->
			if @state.userProgramId?
				return @state.programsById.get(@state.userProgramId)

			return null

		_openClientFile: (clientFileId) ->
			# prevent opening twice on doubleclick; todo: improve this
			unless @state.loadingFile
				@setState {loadingFile: true}
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
							winTitle = nw.Window.get(appWindow.contentWindow).window.document.title
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
					openWindow {page: 'clientFile', clientFileId}, maximize:true, (clientFileWindow) =>
						# prevent window from closing before its ready
						clientFileWindow.on 'close', =>
							clientFileWindow = null
				setTimeout(=>
					@setState {loadingFile: false}
				, 1500)

		_loadInitialData: ->
			Async.parallel [
				(cb) =>
					ActiveSession.persist.clientFiles.list (err, result) =>
						if err
							cb err
							return

						@setState (s) ->
							return {
								clientFileHeaders: result
							}
						, cb
				(cb) =>
					programHeaders = null
					programs = null
					programsById = null
					userProgramLinks = null

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

								programs = Imm.List(results)
									.map (programRevs) -> programRevs.get(0)
								programsById = objectsAsIdMap programs
								cb()
						(cb) =>
							ActiveSession.persist.userProgramLinks.list (err, result) ->
								if err
									cb err
									return

								# TODO why is metadata stripped here?
								userProgramLinks = result.map (link) -> stripMetadata(link)
								cb()
						(cb) =>
							# Figure out userProgramId (We currently assume there can only be one)
							# TODO: Refactor to something a little nicer
							matchingUserProgramLinks = userProgramLinks.filter (link) ->
								return link.get('userName') is global.ActiveSession.userName and
									link.get('status') is 'assigned'

							if matchingUserProgramLinks.size > 1
								console.warn(
									"More than 1 assigned programLink found",
									matchingUserProgramLinks.toJS()
								)

							userProgramLink = matchingUserProgramLinks.get(0, null)
							userProgramId = userProgramLink?.get('programId')
							global.ActiveSession.programId = userProgramId

							@setState (s) ->
								return {
									programsById
									userProgramId
									userProgramLinks
								}
							, cb
					], cb
				(cb) =>
					clientFileProgramLinkHeaders = null
					clientFileProgramLinks = null

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

								clientFileProgramLinks = Imm.List(results)
									# TODO why is metadata stripped here?
									.map (linkRevs) -> stripMetadata linkRevs.get(0)
								cb()
						(cb) =>
							@setState (s) ->
								return {
									clientFileProgramLinks
								}
							, cb
					], cb
				], (err) =>
					if err
						if err instanceof Persist.IOError
							Bootbox.alert "Please check your network connection and try again."
							return

						CrashHandler.handle err
						return

					@setState {
						status: 'ready'
					}

					@_loadSecondaryData()

		# Load data not needed for default tab
		_loadSecondaryData: ->
			Async.parallel [
				(cb) =>
					# TODO Load metrics on first click to metric definition manager
					metricHeaders = null
					metrics = null

					Async.series [
						(cb) ->
							ActiveSession.persist.metrics.list (err, result) =>
								if err
									cb err
									return

								metricHeaders = result
								cb()
						(cb) ->
							Async.map metricHeaders.toArray(), (metricHeader, cb) =>
								metricId = metricHeader.get('id')
								ActiveSession.persist.metrics.readLatestRevisions metricId, 1, cb
							, (err, results) =>
								if err
									cb err
									return

								metrics = Imm.List(results).map (metricRevs) ->
									return metricRevs.first()
								cb()
						(cb) =>
							@setState (s) ->
								return {
									metricsById: objectsAsIdMap metrics
								}
							, cb
					], cb
			], (err) =>
				if err
					if err instanceof Persist.IOError
						Bootbox.alert "Please check your network connection and try again."
						return

					CrashHandler.handle err
					return

				# Done

		getPageListeners: ->
			return {
				# Custom listener for overriding userProgram in ActiveSession
				'override:userProgram': (userProgram) =>
					console.log "Override userProgram to:"
					if userProgram?
						console.log "Program:", userProgram.toJS()
					else
						console.log "None (null)"

					userProgramId = if userProgram? then userProgram.get('id') else null

					global.ActiveSession.programId = userProgramId
					@setState {userProgramId}

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
					@setState (s) ->
						return {
							clientFileHeaders: s.clientFileHeaders.push newFile
						}

				'createRevision:clientFile': (newRev) =>
					@setState (s) ->
						return {
							clientFileHeaders: s.clientFileHeaders.map (cf) ->
								if cf.get('id') is newRev.get('id')
									return newRev

								return cf
						}

				'create:program createRevision:program': (newObj) =>
					@setState (s) ->
						return {
							programsById: s.programsById.set newObj.get('id'), newObj
						}

				'create:clientFileProgramLink': (newObj) =>
					@setState (s) ->
						return {
							clientFileProgramLinks: s.clientFileProgramLinks.push newObj
						}

				'createRevision:clientFileProgramLink': (newRev) =>
					@setState (s) ->
						return {
							clientFileProgramLinks: s.clientFileProgramLinks.map (obj) ->
								if obj.get('id') is newRev.get('id')
									return newRev

								return obj
						}

				'create:metric createRevision:metric': (newObj) =>
					@setState (s) ->
						return {
							metricsById: s.metricsById.set newObj.get('id'), newObj
						}
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

			# Key bindings for search results navigation
			@_attachKeyBindings()

			# Double-ensure that global.ActiveSession.programId lines up with @props.userProgram
			global.ActiveSession.programId = if @props.userProgram then @props.userProgram.get('id') else null

		render: ->
			isAdmin = global.ActiveSession.isAdmin()
			smallHeader = @state.queryText.length > 0 or @state.isSmallHeaderSet

			return R.div({
				id: 'clientSelectionPage'
				className: [
					'animated fadeIn'
					'menuIsOpen' if @state.menuIsOpen
				].join ' '
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
							programsById: @props.programsById
							userProgramLinks: @props.userProgramLinks
							clientFileProgramLinks: @props.clientFileProgramLinks
							metricsById: @props.metricsById
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
								R.div({className: 'subtitleContainer'},
									R.div({
										className: 'subtitleText'
										style: {color: Config.logoSubtitleColor}
									},
										Config.logoSubtitle
									)
									R.div({className: 'versionNumber'},
										"v" + nw.App.manifest.version
									)
								)
							)
							R.div({className: 'searchBoxContainer'},
								noData = @props.clientFileHeaders.isEmpty()

								R.div({className: 'input-group'}
									(unless noData or not isAdmin
										OpenDialogLink({
											className: 'input-group-btn'
											ref: 'openCreateClientSmall'
											dialog: CreateClientFileDialog
											programsById: @props.programsById
										},
											R.button({
												className: 'btn btn-default'
												title: "Add new Client File"
											},
												R.span({className: 'text-success'}, FaIcon('plus'))
											)
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
												programsById: @props.programsById
												disabled: not isAdmin
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
							programsById: @props.programsById
							onRowClick: @_onResultSelection
							displayAllPrograms: @props.displayAllPrograms
							toggleAllPrograms: @props.toggleAllPrograms
						})
					)
				)

				(if @state.menuIsOpen
					MainMenu({
						ref: 'userMenu'
						className: 'menuIsOpen animated fadeInRight'
						isAdmin
						programsById: @props.programsById
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
			queryText: React.PropTypes.string.isRequired

			clientFileHeaders: React.PropTypes.instanceOf(Imm.List).isRequired
			clientFileProgramLinks: React.PropTypes.instanceOf(Imm.List).isRequired
			programsById: React.PropTypes.instanceOf(Imm.Map).isRequired
			toggleAllPrograms: React.PropTypes.func.isRequired

			onRowClick: React.PropTypes.func.isRequired
		}

		getInitialState: -> {
			displayInactive: false
		}

		render: ->
			queryResults = @_filterResults()

			# Add in all program objects this clientFile's a member of
			tableData = queryResults.map (clientFile) =>
				clientFileId = clientFile.get('id')

				programMemberships = null
				if @props.clientFileProgramLinks?
					programMemberships = @props.clientFileProgramLinks
					.filter (link) =>
						link.get('clientFileId') is clientFileId and link.get('status') is "enrolled"
					.map (link) =>
						stripMetadata @props.programsById.get(link.get('programId'))

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
				R.div({id: 'filterSelectionContainer'}
					(if hasInactiveFiles or not hasInactiveFiles
						R.div({className: "toggle animated fadeIn"},
							R.label({}
								R.input({
									onChange: @_toggleInactive
									type: 'checkbox'
									checked: @state.displayInactive
								})
								" Show inactive (#{inactiveClientFiles.size})",
							)
						)
					)
					(if global.ActiveSession.isAdmin() and global.ActiveSession.programId?
						R.div({className: "toggle animated fadeIn"},
							R.label({}
								R.input({
									onChange: @props.toggleAllPrograms
									type: 'checkbox'
									checked: @props.displayAllPrograms
								})
								" All Programs",
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
			queryText: React.PropTypes.string.isRequired
			data: React.PropTypes.instanceOf(Imm.List).isRequired
			hasProgramLinks: React.PropTypes.bool.isRequired
			hasInactiveFiles: React.PropTypes.bool.isRequired

			onRowClick: React.PropTypes.func.isRequired
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
						noDataText: (if @props.queryText
							"No #{Term 'client files'} matching \"#{@props.queryText}\"."
						else
							"No #{Term 'client files'} found."
						)
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
						className: 'leftPadding'
						columnClassName: 'leftPadding'
						width: '150px'
						hidden: not @props.hasProgramLinks
					})
					TableHeaderColumn({
						dataField: 'lastName'
						dataSort: true
						className: 'leftPadding' if not @props.hasProgramLinks
						columnClassName: 'leftPadding' if not @props.hasProgramLinks
					}, "Last Name")
					TableHeaderColumn({
						dataField: 'givenNames'
						dataSort: true
						className: 'visibleColumn'
						columnClassName: 'visibleColumn'
					}, "Given Names")
					TableHeaderColumn({
						dataField: 'recordId'
						dataSort: true
						className: 'rightPadding' if Config.clientFileRecordId.isEnabled and not @props.displayInactive
						columnClassName: 'rightPadding' if Config.clientFileRecordId.isEnabled and not @props.displayInactive
						headerAlign: 'right'
						dataAlign: 'right'
						hidden: not Config.clientFileRecordId.isEnabled
					}, Config.clientFileRecordId.label)
					TableHeaderColumn({
						dataField: 'status'
						dataSort: true
						headerAlign: 'right'
						dataAlign: 'right'
						className: 'rightPadding' if @props.displayInactive
						columnClassName: 'rightPadding' if @props.displayInactive
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
