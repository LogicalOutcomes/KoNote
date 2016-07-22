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

	Gui = win.require 'nw.gui'
	Window = Gui.Window.get()

	Spinner = require('./spinner').load(win)
	MainMenu = require('./mainMenu').load(win)
	BrandWidget = require('./brandWidget').load(win)
	OrderableTable = require('./orderableTable').load(win)
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

				isLoading: false
				loadingMessage: ""
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
				isLoading: @state.isLoading
				loadingMessage: @state.loadingMessage

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
			@setState {
				isLoading: true
				loadingMessage: "Loading Client File..."
			}

			openWindow {
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
					@_openClientFile(newFile.get('id')) unless global.isSeeding

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

				queryText: ''
				queryResults: Imm.List()
				showingDormant: false
				quantityDormant: 0

				orderedQueryResults: Imm.List()
				hoverClientId: null

				managerLayer: null
			}

		componentDidMount: ->
			setTimeout(=>
				@_refreshResults()

				# Show and focus this window
				Window.show()
				Window.focus()

				# Fire 'loaded' event for loginPage to hide itself
				global.ActiveSession.persist.eventBus.trigger 'clientSelectionPage:loaded'

				@_attachKeyBindings()

			, 250)

		componentDidUpdate: (oldProps, oldState) ->
			if @props.clientFileHeaders isnt oldProps.clientFileHeaders
				@_refreshResults()

			if @state.queryText isnt oldState.queryText
				@_refreshResults()

		render: ->
			isAdmin = global.ActiveSession.isAdmin()
			smallHeader = @state.queryText.length > 0 or @state.isSmallHeaderSet

			# Add in all program objects this clientFile's a member of

			queryResults = @state.queryResults
			.map (clientFile) =>
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
							name: @state.managerLayer
							clientFileHeaders: @props.clientFileHeaders
							programs: @props.programs
							userProgramLinks: @props.userProgramLinks
							clientFileProgramLinks: @props.clientFileProgramLinks
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
						R.div({
							className: [
								'results'
								if smallHeader then 'show' else 'hidden'
							].join ' '
						},
							if @_hasDormant()
								R.div({id: 'filterSelectionContainer'}
									R.span({id: 'toggleDeactivated'},
										R.div({className: "checkbox"},
											R.label({}
												R.input({
													onChange: @_toggleDormant
													type: 'checkbox'
													checked: @state.showingDormant
												})
												"Show deactivated (#{@state.quantityDormant})",
											)
										)
									)
								)
							OrderableTable({
								tableData: queryResults
								noMatchesMessage: "No #{Term 'client file'} matches for \"#{@state.queryText}\""
								onSortChange: (orderedQueryResults) => @setState {orderedQueryResults}
								sortByData: ['clientName', 'last']
								key: ['id']
								rowClass: (dataPoint) =>
									'active' if @state.hoverClientId is dataPoint.get('id')
									'deactivatedClientFile' unless dataPoint.get('status') is 'active'
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
											programs = dataPoint.get('programs')
											ProgramBubbles({programs})
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
										name: "Status"
										dataPath: ['status']
										isDisabled: not @state.showingDormant
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
					MainMenu({
						ref: 'userMenu'
						className: 'menuIsOpen animated fadeInRight'
						programs: @props.programs
						userProgram: @props.userProgram
						managerLayer: @state.managerLayer

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
				mainMenuNode = ReactDOM.findDOMNode(@refs.userMenu)
				$(mainMenuNode).addClass('slideOutRight')

				@setState {managerLayer: null}

				setTimeout(=>
					@setState {menuIsOpen: false}
				, 400)
			else
				@setState {menuIsOpen: true}

		_refreshResults: ->
			# Return all results if search query is empty
			if @state.queryText.trim().length is 0
				if @state.showingDormant is false
					# TODO: Move this logic to render
					queryResults = @props.clientFileHeaders
					.filter (clientFile) ->
						clientFile.get('status') is 'active'

					@setState {queryResults}
				else
					queryResults = @props.clientFileHeaders
				@setState {queryResults}
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
		_toggleDormant: ->
			if @state.showingDormant is true
				queryResults = @props.clientFileHeaders
				.filter (clientFile) ->
					clientFile.get('status') is 'active'
				showingDormant = false
				@setState {queryResults, showingDormant}
			else
				queryResults = @props.clientFileHeaders
				showingDormant = true
				@setState {queryResults, showingDormant}
		_hasDormant: ->
			activeHeaders = @props.clientFileHeaders
				.filter (clientFile) ->
					clientFile.get('status') is 'active'
			if @props.clientFileHeaders.size is activeHeaders.size
				return false
			else
				quantityDormant = @props.clientFileHeaders.size - activeHeaders.size
				@setState {quantityDormant}
				return true
		_showAll: ->
			@setState {isSmallHeaderSet: true, queryText: ''}
		_home: ->
			@setState {isSmallHeaderSet: false, queryText: ''}
		_onResultSelection: (clientFileId, event) ->
			@setState {hoverClientId: clientFileId}
			@props.openClientFile(clientFileId)



	return ClientSelectionPage

module.exports = {load}