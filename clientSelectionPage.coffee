# Libraries from Node.js context
Imm = require 'immutable'

Config = require './config'
Persist = require './persist'

load = (win) ->
	# Libraries from browser context
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM
	Spinner = require('./spinner').load(win)
	{FaIcon, openWindow, renderName, showWhen} = require('./utils').load(win)

	do ->
		clientFileList = null

		init = ->
			render()
			loadData()
			registerListeners()

		process.nextTick init

		render = ->
			React.render new ClientSelectionPage({
				clientFileList
			}), $('#container')[0]

		loadData = ->
			Persist.ClientFile.list (err, result) ->
				if err
					console.error err.stack
					Bootbox.alert "Could not load client file information."
					return

				clientFileList = result
				render()

		registerListeners = ->
			# TODO new client file listener

	ClientSelectionPage = React.createFactory React.createClass
		componentDidMount: ->
			@refs.searchBox.getDOMNode().focus()
		getInitialState: ->
			return {
				isSmallHeaderSet: false
				queryText: ''
			}
		_isLoading: ->
			return @props.clientFileList is null
		render: ->
			smallHeader = @state.queryText.length > 0 or @state.isSmallHeaderSet

			results = null
			unless @_isLoading()
				# TODO test perf
				results = @_getResultsList()

			return R.div({className: 'clientSelectionPage'},
				Spinner({
					isVisible: @_isLoading()
					isOverlay: true
				})
				R.div({
					className: [
						'header'
						if smallHeader then 'small' else ''
						showWhen not @_isLoading()
					].join ' '
				},
					R.div({className: 'logoContainer'},
						R.img({src: 'customer-logo-lg.png'})
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
							placeholder: "Search for a client's profile..."
						})
					)
				)
				R.div({
					className: [
						'smallHeaderLogo'
						if smallHeader then 'show' else 'hidden'
						showWhen not @_isLoading()
					].join ' '
				},
					R.img({src: 'customer-logo-lg.png'})
				)
				R.div({
					className: [
						'results'
						if smallHeader then 'show' else 'hidden'
						showWhen not @_isLoading()
					].join ' '
				},
					(if results?
						(results.map (result) =>
							R.div({
								className: 'result'
								onClick: @_onResultSelection.bind(null, result.get('clientId'))
							},
								renderName result.get('name')
							)
						).toJS()
					else
						[]
					)...
				)
			)
		_getResultsList: ->
			if @state.queryText.trim() is ''
				return Imm.List()

			queryParts = Imm.fromJS(@state.queryText.split(' '))
			.map (p) -> p.toLowerCase()

			return @props.clientFileList
			.filter (clientFile) ->
				firstName = clientFile.getIn(['name', 'first']).toLowerCase()
				lastName = clientFile.getIn(['name', 'last']).toLowerCase()

				return queryParts
				.every (part) ->
					return firstName.includes(part) or lastName.includes(part)
		_updateQueryText: (event) ->
			@setState {queryText: event.target.value}

			if event.target.value.length > 0
				@setState {isSmallHeaderSet: true}
		_onSearchBoxBlur: (event) ->
			if @state.queryText is ''
				@setState {isSmallHeaderSet: false}
		_onResultSelection: (clientId, event) ->
			openWindow {
				page: 'clientFile'
				clientId
			}

module.exports = {load}
