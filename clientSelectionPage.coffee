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

	ProgramManagerDialog = require('./programManagerDialog').load(win)
	AccountManagerDialog = require('./accountManagerDialog').load(win)
	CrashHandler = require('./crashHandler').load(win)
	CreateClientFileDialog = require('./createClientFileDialog').load(win)
	LayeredComponentMixin = require('./layeredComponentMixin').load(win)
	Spinner = require('./spinner').load(win)
	BrandWidget = require('./brandWidget').load(win)	
	{FaIcon, openWindow, renderName, showWhen, stripMetadata} = require('./utils').load(win)

	ClientSelectionPage = React.createFactory React.createClass
		getInitialState: ->
			return {
				isLoading: true
				clientFileHeaders: Imm.List()
				programs: Imm.List()
			}

		init: ->
			console.log "Starting load"
			@_loadData()

		deinit: (cb=(->)) ->
			# Nothing need be done
			cb()

		suggestClose: ->
			@props.closeWindow()

		render: ->
			return ClientSelectionPageUi({
				isLoading: @state.isLoading
				clientFileHeaders: @state.clientFileHeaders
				programs: @state.programs
			})

		_loadData: ->
			clientFileHeaders = null
			programHeaders = null
			programs = null

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
			], (err) =>
				if err
					if err instanceof Persist.IOError
						console.error err
						console.error err.stack
						@setState {loadErrorType: 'io-error'}
						return

					CrashHandler.handle err
					return

				# Data loaded successfully, fill up state
				@setState {
					isLoading: false
					programs
					clientFileHeaders
				}

		getPageListeners: ->
			return {
				'create:clientFile': (newFile) =>
					clientFileHeaders = @state.clientFileHeaders.push newFile
					@setState {clientFileHeaders}, =>
						openWindow {
							page: 'clientFile'
							clientFileId: newFile.get('id')
						}
				'create:program createRevision:program': (newRev) =>
					programId = newRev.get('id')
					# Updating or creating new program?
					existingProgram = @state.programs.find (program) =>
						program.get('id') is programId

					@setState (state) =>
						if existingProgram?
							programIndex = state.programs.indexOf existingProgram
							programs = state.programs.set programIndex, newRev
						else
							programs = state.programs.push newRev

						return {programs}
			}

	ClientSelectionPageUi = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				isSmallHeaderSet: false
				menuIsOpen: false

				queryText: ''
				queryResults: Imm.List()				
				hoverClientId: null
			}

		componentDidUpdate: (oldProps, oldState) ->
			# If loading just finished
			if oldProps.isLoading and not @props.isLoading
				setTimeout(=>
					@refs.searchBox.getDOMNode().focus()
				, 100)

			if @props.clientFileHeaders isnt oldProps.clientFileHeaders
				@_refreshResults

			if @state.queryText isnt oldState.queryText
				@_refreshResults()

		componentDidMount: ->
			@_refreshResults()
			@_attachKeyBindings()

		render: ->
			smallHeader = @state.queryText.length > 0 or @state.isSmallHeaderSet

			return R.div({
					id: 'clientSelectionPage'
					className: if @state.menuIsOpen then 'openMenu' else ''
				},
				R.a({
					id: 'expandMenuButton'
					onClick: @_toggleUserMenu
				}, 
					FaIcon 'bars'
				)
				R.div({
					id: 'mainContainer'
					onClick: if @state.menuIsOpen then @_toggleUserMenu
				},					
					R.div({id: 'main'},
						Spinner({
							isVisible: @props.isLoading
							isOverlay: true
						})						
						R.header({
							className: [
								if smallHeader then 'small' else ''
								showWhen not @props.isLoading
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
							R.div({className: 'searchBoxContainer input-group'},
								R.input({
									className: 'searchBox form-control'
									ref: 'searchBox'
									type: 'text'
									onChange: @_updateQueryText
									placeholder: "Search for a #{Term 'client'}'s profile..."
									value: @state.queryText
								}
									R.span({
										className: 'input-group-btn'
									},
										R.button({
											className: "btn btn-default"
											onClick: @_showAll
										},
											'Show All'
										)
									)
								)
							)
						)
						R.div({
							className: [
								'smallHeaderLogo'
								if smallHeader then 'show' else 'hidden'
								showWhen not @props.isLoading
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
								showWhen not @props.isLoading
							].join ' '
						},
							(@state.queryResults.map (result) =>
								R.div({
									key: "result-" + result.get('id')
									className: [
										"hover" if @state.hoverClientId is result.get('id')
										"result"										
									].join ' '
									onClick: @_onResultSelection.bind(null, result.get('id'))
								}
									R.span({className: 'recordId'}, 
										if result.has('recordId') and result.get('recordId').length > 0
											Config.clientFileRecordId.label + " #{result.get('recordId')}"
									)
									renderName result.get('clientName')
								)
							).toJS()
						)
					)
				)
				R.aside({
					id: 'menuContainer'
					ref: 'userMenu'
					className: if @state.menuIsOpen then 'isOpen' else ''
				}
					R.div({id: 'menuContent'}
						R.div({id: 'avatar'}, FaIcon('user'))
						R.h3({}, global.ActiveSession.userName)
						@_renderUserMenuList(global.ActiveSession.isAdmin())
					)
				)
			)

		_renderUserMenuList: (isAdmin) ->
			return R.ul({},
				UserMenuItem({
					title: "New #{Term 'Client File'}"
					dialog: CreateClientFileDialog
					icon: 'folder-open'
					data: {
						clientFileHeaders: @props.clientFileHeaders
					}
				})
				UserMenuItem({
					isVisible: isAdmin
					title: "#{Term 'Account'} Manager"
					dialog: AccountManagerDialog
					icon: 'users'
				})
				UserMenuItem({
					isVisible: isAdmin
					title: Term 'Programs'
					dialog: ProgramManagerDialog
					icon: 'users'
					data: {
						programs: @props.programs
						clientFileHeaders: @props.clientFileHeaders
					}
				})
			)

		_toggleUserMenu: ->
			@setState {menuIsOpen: !@state.menuIsOpen}		

		_attachKeyBindings: ->
			searchBox = @refs.searchBox.getDOMNode()

			# $(searchBox).on 'submit', (event) -> event.preventDefault()

			# Key-bindings for searchBox
			$(searchBox).on 'keydown', (event) =>
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
						$('.hover')[0].click()
						return false

		_shiftHoverClientId: (modifier) ->
			hoverClientId = null
			queryResults = @state.queryResults

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

		_refreshResults: ->
			# Return all results if search query is empty
			if @state.queryText.trim().length is 0
				@setState {queryResults: @props.clientFileHeaders}
				return

			# Calculate query parts & results
			queryParts = Imm.fromJS(@state.queryText.split(' '))
			.map (p) -> p.toLowerCase()


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
			openWindow {
				page: 'clientFile'
				clientFileId
			}


	UserMenuItem = React.createFactory React.createClass
		mixins: [LayeredComponentMixin]
		getDefaultProps: ->
			return {
				isVisible: true
			}
		getInitialState: ->
			return {
				isOpen: false
			}

		render: ->
			return R.li({className: showWhen(@props.isVisible)},
				R.div({
					onClick: @_openMenu
				}, 
					FaIcon(@props.icon)
					@props.title
				)
			)
		renderLayer: ->
			unless @state.isOpen
				return R.div()

			# Default user menu functions
			defaultProps = {
				onClose: @_closeMenu
				onCancel: @_closeMenu
				onSuccess: @_closeMenu					
			}
			# Extend with custom data/function props
			propsWithData = _.extend defaultProps, @props.data

			return @props.dialog propsWithData

		_openMenu: ->
			@setState {isOpen: true}
		_closeMenu: ->
			@setState {isOpen: false}

	return ClientSelectionPage

module.exports = {load}
