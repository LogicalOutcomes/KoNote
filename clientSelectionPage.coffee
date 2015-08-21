# Libraries from Node.js context
Imm = require 'immutable'

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

	AccountManagerDialog = require('./accountManagerDialog').load(win)
	CrashHandler = require('./crashHandler').load(win)
	CreateClientFileDialog = require('./createClientFileDialog').load(win)
	Dialog = require('./dialog').load(win)
	LayeredComponentMixin = require('./layeredComponentMixin').load(win)
	Spinner = require('./spinner').load(win)
	BrandWidget = require('./brandWidget').load(win)	
	{FaIcon, openWindow, renderName, showWhen} = require('./utils').load(win)

	ClientSelectionPage = React.createFactory React.createClass
		getInitialState: ->
			return {
				isLoading: true
				clientFileList: null
			}

		init: ->
			@_loadData()

		deinit: ->
			# Nothing need be done

		suggestClose: ->
			@props.closeWindow()

		render: ->
			return new ClientSelectionPageUi({
				isLoading: @state.isLoading
				clientFileList: @state.clientFileList
			})

		_loadData: ->
			ActiveSession.persist.clientFiles.list (err, result) =>
				if err
					if err instanceof Persist.IOError
						Bootbox.alert """
							Please check your network connection and try again.
						""", =>
							@props.closeWindow()
						return

					CrashHandler.handle err
					return

				@setState (state) =>
					return {
						isLoading: false
						clientFileList: result
					}

		getPageListeners: ->
			return {
				'create:clientFile': (newFile) =>
					@setState (state) => clientFileList: state.clientFileList.push newFile
			}

	ClientSelectionPageUi = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				isSmallHeaderSet: false
				queryText: ''
				menuIsOpen: false
			}

		componentDidUpdate: (oldProps, oldState) ->
			# If loading just finished
			if oldProps.isLoading and (not @props.isLoading)
				setTimeout(=>
					@refs.searchBox.getDOMNode().focus()
				, 100)

		render: ->
			smallHeader = @state.queryText.length > 0 or @state.isSmallHeaderSet

			results = null
			unless @props.isLoading
				results = @_getResultsList()

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
							R.div({className: 'searchBoxContainer'},
								R.input({
									className: 'searchBox form-control'
									ref: 'searchBox'
									type: 'text'
									onChange: @_updateQueryText
									onBlur: @_onSearchBoxBlur
									placeholder: "Search for a #{Term 'client'}'s profile..."
									value: @state.queryText
								})
							)
							R.div({
								className: 'showAllClients'
								style: {color: 'grey'}
								onClick: @_showAll
							},
								'[ show all ]'
							)
						)
						R.div({
							className: [
								'smallHeaderLogo'
								if smallHeader then 'show' else 'hidden'
								showWhen not @props.isLoading
							].join ' '
						},
							R.img({src: Config.customerLogoLg})
						)
						R.div({
							className: [
								'results'
								if smallHeader then 'show' else 'hidden'
								showWhen not @props.isLoading
							].join ' '
						},
							(if results?
								(results.map (result) =>
									R.div({
										className: 'result'
										onClick: @_onResultSelection.bind(null, result.get('id'))
									}
										R.span({
											className: 'recordId'
										}, if result.has('recordId') and result.get('recordId').length > 0 then Config.clientFileRecordId.label + " #{result.get('recordId')}"),
									renderName result.get('clientName')
									)
								).toJS()
							else
								[]
							)...
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
				})
				UserMenuItem({
					isVisible: isAdmin
					title: "#{Term 'Account'} Manager"
					dialog: AccountManagerDialog
					icon: 'users'
				})
			)

		_toggleUserMenu: ->
			@setState {menuIsOpen: !@state.menuIsOpen}		

		_getResultsList: ->
			if @state.queryText.trim() is ''
				return @props.clientFileList

			queryParts = Imm.fromJS(@state.queryText.split(' '))
			.map (p) -> p.toLowerCase()

			return @props.clientFileList
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
		_updateQueryText: (event) ->
			@setState {queryText: event.target.value}

			if event.target.value.length > 0
				@setState {isSmallHeaderSet: true}
		_showAll: ->
			@setState {isSmallHeaderSet: true}
			$('.showAllClients').hide()
		_onSearchBoxBlur: (event) ->
			if @state.queryText is ''
				@setState {isSmallHeaderSet: false}
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
					onClick: @_open
				}, 
					FaIcon(@props.icon)
					@props.title
				)
			)
		renderLayer: ->
			unless @state.isOpen
				return R.div()

			return @props.dialog({
				onClose: =>
					@setState {isOpen: false}
				onCancel: =>
					@setState {isOpen: false}
				onSuccess: (clientFileId) =>
					@setState {isOpen: false}					
					if clientFileId
						openWindow {
							page: 'clientFile'
							clientFileId
						}
			})
		_open: ->
			@setState {isOpen: true}

	return ClientSelectionPage

module.exports = {load}
