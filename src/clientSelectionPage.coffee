# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Libraries from Node.js context
Imm = require 'immutable'
Async = require 'async'
_ = require 'underscore'

Config = require './config'
Term = require './term'
Persist = require './persist'

load = (win) ->
	# Libraries from browser context
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM
	Gui = win.require 'nw.gui'
	Window = Gui.Window.get()

	ManagerLayer = require('./managerLayer').load(win)		
	Spinner = require('./spinner').load(win)
	BrandWidget = require('./brandWidget').load(win)	
	OrderableTable = require('./orderableTable').load(win)
	OpenDialogLink = require('./openDialogLink').load(win)
	ProgramBubbles = require('./programBubbles').load(win)

	CreateClientFileDialog = require('./createClientFileDialog').load(win)

	CrashHandler = require('./crashHandler').load(win)
	{FaIcon, openWindow, renderName, showWhen, stripMetadata} = require('./utils').load(win)

	ClientSelectionPage = React.createFactory React.createClass
		getInitialState: ->
			return {
				status: 'init'

				isLoading: false
				loadingMessage: ""
				clientFileHeaders: Imm.List()
				programs: Imm.List()
				clientFileProgramLinks: Imm.List()
			}

		init: ->
			@props.setWindowTitle """
				#{Config.productName} (#{global.ActiveSession.userName})
			"""
			@_loadData()

		deinit: (cb=(->)) ->
			# Nothing need be done
			cb()

		suggestClose: ->
			@props.closeWindow()		

		render: ->
			unless @state.status is 'ready' then return R.div({})

			return ClientSelectionPageUi {
				openClientFile: @_openClientFile

				status: @state.status				
				isLoading: @state.isLoading
				loadingMessage: @state.loadingMessage

				clientFileHeaders: @state.clientFileHeaders
				clientFileProgramLinks: @state.clientFileProgramLinks
				programs: @state.programs
				metricDefinitions: @state.metricDefinitions
			}

		_openClientFile: (clientFileId) ->
			@setState {
				isLoading: true
				loadingMessage: "Loading Client File..."
			}

			clientFileWindow = openWindow {
				page: 'clientFile'
				clientFileId
			}

			global.ActiveSession.persist.eventBus.once 'clientFilePage:loaded', =>
				@setState {
					isLoading: false
					loadingMessage: ''
				}

		_setStatus: (status) ->
			@setState {status}

		_loadData: ->
			clientFileHeaders = null
			programHeaders = null
			programs = null
			clientFileProgramLinkHeaders = null
			clientFileProgramLinks = null
			metricDefinitionHeaders = null
			metricDefinitions = null

			Async.series [
				(cb) =>
					ActiveSession.persist.clientFiles.list (err, result) =>
						if err
							cb err
							return

						clientFileHeaders = result
						cb()
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
						cb()
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
				(cb) =>
					ActiveSession.persist.metrics.list (err, result) =>
						if err
							cb err
							return

						metricDefinitionHeaders = result
						cb()
				(cb) =>
					Async.map metricDefinitionHeaders.toArray(), (metricDefinitionHeader, cb) =>
						metricDefinitionId = metricDefinitionHeader.get('id')
						ActiveSession.persist.metrics.readLatestRevisions metricDefinitionId, 1, cb
					, (err, results) =>
						if err
							cb err
							return

						metricDefinitions = Imm.List(results)
						.map (metricDefinition) -> stripMetadata metricDefinition.first()

						cb()
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
					clientFileHeaders
					clientFileProgramLinks
					metricDefinitions
				}

		getPageListeners: ->
			return {

				'create:clientFile': (newFile) =>
					clientFileHeaders = @state.clientFileHeaders.push newFile
					@setState {clientFileHeaders}
					@_openClientFile(newFile.get('id')) unless global.isSeeding

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

				'create:metric createRevision:metric': (newRev) =>
					metricDefinitionId = newRev.get('id')
					# Updating or creating metric?
					existingMetricDefinition = @state.metricDefinitions
					.find (metricDefinition) -> metricDefinition.get('id') is metricDefinitionId

					@setState (state) ->
						if existingMetricDefinition?
							definitionIndex = state.metricDefinitions.indexOf existingMetricDefinition
							metricDefinitions = state.metricDefinitions.set definitionIndex, newRev
						else
							metricDefinitions = state.metricDefinitions.push newRev

						return {metricDefinitions}

			}

	ClientSelectionPageUi = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				isSmallHeaderSet: false
				menuIsOpen: false

				queryText: ''
				queryResults: Imm.List()

				orderedQueryResults: Imm.List()
				hoverClientId: null

				managerLayer: null
			}

		componentDidMount: ->
			@_refreshResults()

			setTimeout(=>
				# Show and focus this window
				Window.show()
				Window.focus()

				# Fire 'loaded' event for loginPage to hide itself
				global.ActiveSession.persist.eventBus.trigger 'clientSelectionPage:loaded'

				@_attachKeyBindings()
				@refs.searchBox.focus()
			, 500)			

		componentDidUpdate: (oldProps, oldState) ->
			if @props.clientFileHeaders isnt oldProps.clientFileHeaders
				@_refreshResults()

			if @state.queryText isnt oldState.queryText
				@_refreshResults()

		render: ->
			isAdmin = global.ActiveSession.isAdmin()
			smallHeader = @state.queryText.length > 0 or @state.isSmallHeaderSet	

			# Add in all program objects this clientFile's a member of
			queryResults = @state.queryResults.map (clientFile) =>
				clientFileId = clientFile.get('id')

				programMemberships = @props.clientFileProgramLinks
				.filter (link) =>
					link.get('clientFileId') is clientFileId and link.get('status') is "enrolled"
				.map (link) =>
					@props.programs.find (program) -> program.get('id') is link.get('programId')

				clientFile.set('programs', programMemberships)

			return R.div({
					id: 'clientSelectionPage'
					className: if @state.menuIsOpen then 'openMenu' else ''
			},
				Spinner {
					isOverlay: true
					isVisible: @props.isLoading
					message: @props.loadingMessage
				}

				R.a({
					id: 'expandMenuButton'
					className: 'menuIsOpen' if @state.menuIsOpen
					onClick: =>
						@_toggleUserMenu()
						@refs.searchBox.focus() if @refs.searchBox? and @state.menuIsOpen
				},
					if @state.menuIsOpen
						FaIcon('times')
					else
						"Menu"
				)
				R.div({
					id: 'mainContainer'					
				},
					(if @state.managerLayer?
						ManagerLayer({
							# Settings
							name: @state.managerLayer
							# Data
							clientFileHeaders: @props.clientFileHeaders							
							programs: @props.programs
							clientFileProgramLinks: @props.clientFileProgramLinks
							metricDefinitions: @props.metricDefinitions
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
								R.img({src: Config.customerLogoLg})
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
											dialog: CreateClientFileDialog
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
								src: Config.customerLogoLg
								onClick: @_home
							})
						)
						R.div({
							className: [
								'results'
								if smallHeader then 'show' else 'hidden'
							].join ' '
						},
							OrderableTable({
								tableData: queryResults
								noMatchesMessage: "No #{Term 'client file'} matches for \"#{@state.queryText}\""
								onSortChange: (orderedQueryResults) => @setState {orderedQueryResults}
								sortByData: ['clientName', 'last']
								key: ['id']
								rowClass: (dataPoint) =>
									'active' if @state.hoverClientId is dataPoint.get('id')
								onClickRow: (dataPoint) =>
									@_onResultSelection.bind null, dataPoint.get('id')

								columns: [
									{
										name: Term 'Programs'
										dataPath: ['programs']
										cellClass: 'programsCell'
										isNotOrderable: true
										nameIsVisible: false
										value: (dataPoint) ->
											ProgramBubbles({programs: dataPoint.get('programs')})
									}
									{
										name: "Last Name"
										dataPath: ['clientName', 'last']
									}
									{
										name: "Given Name(s)"
										dataPath: ['clientName', 'first']
										extraPath: ['clientName', 'middle']
									}
									{
										name: Config.clientFileRecordId.label
										dataPath: ['recordId']
										isDisabled: not Config.clientFileRecordId.isEnabled
									}
								]
							})
						)
					)
				)

				(if @state.menuIsOpen
					R.aside({
						id: 'menuContainer'
						ref: 'userMenu'
						className: 'menuIsOpen animated fadeInRight'
					},
						R.div({id: 'menuContent'},
							R.div({id: 'userMenu'},
								R.div({},
									R.div({id: 'avatar'}, FaIcon('user'))
									R.h3({}, global.ActiveSession.userName)
								)
							)
							R.div({id: 'featureMenu'},
								R.ul({},
									UserMenuItem({									
										title: "New #{Term 'Client File'}"
										icon: 'folder-open'
										dialog: CreateClientFileDialog
										onClick: @_updateManagerLayer.bind null, null
									})
									UserMenuItem({
										isVisible: isAdmin
										title: "User #{Term 'Accounts'}"
										icon: 'key'
										onClick: @_updateManagerLayer.bind null, 'accountManagerTab'
										isActive: @state.managerLayer is 'accountManagerTab'
									})
									UserMenuItem({
										title: Term 'Programs'
										icon: 'users'
										onClick: @_updateManagerLayer.bind null, 'programManagerTab'
										isActive: @state.managerLayer is 'programManagerTab'
									})								
									UserMenuItem({
										isVisible: isAdmin
										title: "#{Term 'Event'} Types"
										icon: 'calendar-o'
										onClick: @_updateManagerLayer.bind null, 'eventTypeManagerTab'
										isActive: @state.managerLayer is 'eventTypeManagerTab'
									})
									UserMenuItem({
										title: Term 'Metrics'
										icon: 'line-chart'
										onClick: @_updateManagerLayer.bind null, 'metricDefinitionManagerTab'
										isActive: @state.managerLayer is 'metricDefinitionManagerTab'
									})
									UserMenuItem({
										isVisible: isAdmin
										title: "Export Data"
										icon: 'upload'
										onClick: @_updateManagerLayer.bind null, 'exportManagerTab'
										isActive: @state.managerLayer is 'exportManagerTab'
									})
									UserMenuItem({
										title: "My #{Term 'Account'}"
										icon: 'cog'
										onClick: @_updateManagerLayer.bind null, 'myAccountManagerTab'
										isActive: @state.managerLayer is 'myAccountManagerTab'
									})
								)
							)
						)
					)
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
						@_shiftHoverClientId(1)
					when 38 # Up arrow
						event.preventDefault()
						@_shiftHoverClientId(-1)
					when 27 # Esc
						@setState hoverClientId: null
					when 13 # Enter
						$active = $('.active')
						return unless $active.length
						$active[0].click()
						return false

		_shiftHoverClientId: (modifier) ->
			hoverClientId = null
			queryResults = @state.orderedQueryResults

			return if queryResults.isEmpty()

			# Get our current index position
			currentResultIndex = queryResults.findIndex (result) =>
				return result.get('id') is @state.hoverClientId

			nextIndex = currentResultIndex + modifier

			# Skip to first/last if first-run or next is non-existent
			if not queryResults.get(nextIndex)? or not @state.hoverClientId?
				if modifier > 0
					hoverClientId = queryResults.first().get('id')
				else
					hoverClientId = queryResults.last().get('id')

				@setState {hoverClientId}
				return

			# No wacky skip behaviour needed, move to next/previous result
			hoverClientId = queryResults.get(nextIndex).get('id')
			@setState {hoverClientId}

		_updateManagerLayer: (managerLayer) ->
			@setState {managerLayer}

		_toggleUserMenu: ->
			if @state.menuIsOpen
				$(@refs.userMenu).addClass('slideOutRight')

				@setState {managerLayer: null}

				setTimeout(=>
					@setState {
						menuIsOpen: false						
					}
				, 400)
			else
				@setState {menuIsOpen: true}

		_refreshResults: ->
			# Return all results if search query is empty
			if @state.queryText.trim().length is 0
				@setState {queryResults: @props.clientFileHeaders}
				return

			# Split into query parts
			queryParts = Imm.fromJS(@state.queryText.split(' '))
			.map (p) -> p.toLowerCase()

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

			@setState {queryResults}

		_updateQueryText: (event) ->
			@setState {queryText: event.target.value}

			if event.target.value.length > 0
				@setState {isSmallHeaderSet: true}

		_showAll: ->
			@setState {isSmallHeaderSet: true, queryText: ''}
		_home: ->
			@setState {isSmallHeaderSet: false, queryText: ''}
		_onResultSelection: (clientFileId, event) ->
			@setState {hoverClientId: clientFileId}
			@props.openClientFile(clientFileId)


	UserMenuItem = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		getDefaultProps: ->
			return {
				isVisible: true
				isActive: false
				onClick: ->
				dialog: null
			}

		render: ->
			return R.li({
				className: [
					'active' if @props.isActive
					showWhen @props.isVisible
				].join ' '
				onClick: @props.onClick
			},
				if @props.dialog?
					OpenDialogLink({dialog: @props.dialog},
						FaIcon(@props.icon)
						@props.title
					)
				else
					R.div({},
						FaIcon(@props.icon)
						@props.title
					)
			)	


	return ClientSelectionPage

module.exports = {load}
