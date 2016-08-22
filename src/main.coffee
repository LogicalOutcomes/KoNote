# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Here, we kick off the appropriate page rendering code based on what page ID
# is specified in the URL.
#
# Special care is taken to provide the correct "window" object.  JS code that
# has been require()'d can't rely on `window` being set to the correct object.
# It seems that only code that was included via a <script> tag can rely on
# `window` being set correctly.

_ = require 'underscore'

defaultPageId = 'login'
pageModulePathsById = {
	login: './loginPage'
	clientSelection: './clientSelectionPage'
	clientFile: './clientFilePage'
	newProgNote: './newProgNotePage'
	printPreview: './printPreviewPage'
	newInstallation: './newInstallationPage'
}

init = (win) ->
	Assert = require 'assert'
	Backbone = require 'backbone'
	QueryString = require 'querystring'
	Imm = require 'immutable'

	isRefreshing = null

	Config = require('./config')

	document = win.document
	React = win.React
	ReactDOM = win.ReactDOM

	CrashHandler = require('./crashHandler').load(win)
	HotCodeReplace = require('./hotCodeReplace').load(win)
	{getTimeoutListeners} = require('./timeoutDialog').load(win)

	Gui = win.require 'nw.gui'
	nwWin = Gui.Window.get(win)

	# Handle any uncaught errors.
	# Generally, errors should be passed directly to CrashHandler instead of
	# being thrown so that the error brings down only one window.  Errors that
	# reach this event handler will bring down the entire application, which is
	# usually less desirable.
	process.on 'uncaughtException', (err) ->
		CrashHandler.handle err

	# Application menu bar required for osx copy-paste functionality
	if process.platform is 'darwin'
		menuBar = new Gui.Menu({type: 'menubar'})
		menuBar.createMacBuiltin(Config.productName)
		Gui.Window.get().menu = menuBar

	containerElem = document.getElementById('container')

	pageComponent = null
	isLoggedIn = null
	chokidarListener = null
	allListeners = null

	# Build page params object, assign default pageId if none provided
	pageParameters = QueryString.parse(win.location.search.substr(1))
	pageParameters.page = defaultPageId unless pageParameters.page?

	win.pageParameters = pageParameters

	process.nextTick =>
		# Configure if application is just starting
		global.HCRSavedState ||= {}

		# Render and setup page
		renderPage(pageParameters)
		initPage()


	renderPage = (requestedPage) =>
		# Decide what page to render based on the page parameter
		# URL would look something like `.../main.html?page=client`
		pageModulePath = pageModulePathsById[requestedPage.page]

		# Load the page module
		pageComponentClass = require(pageModulePath).load(win, requestedPage)

		# Render page in window
		pageComponent = ReactDOM.render pageComponentClass({
			navigateTo: (pageParams) =>
				pageComponent.deinit ->
					unregisterPageListeners() if isLoggedIn
					nwWin.removeListener 'close', onWindowCloseEvent
					ReactDOM.unmountComponentAtNode containerElem
					win.location.href = "main.html?" + QueryString.stringify(pageParams)

			closeWindow: =>
				nwWin.hide()
				pageComponent.deinit =>
					unregisterPageListeners() if isLoggedIn
					ReactDOM.unmountComponentAtNode containerElem
					nwWin.close true

			refreshWindow: =>
				pageComponent.deinit =>
					unregisterPageListeners() if isLoggedIn
					nwWin.removeListener 'close', onWindowCloseEvent
					ReactDOM.unmountComponentAtNode containerElem
					nwWin.reloadIgnoringCache()

			maximizeWindow: =>
				nwWin.maximize()

			setWindowTitle: (newTitle) =>
				nwWin.title = newTitle

		}), containerElem

	initPage = =>
		# Make sure up this page has the required methods
		Assert pageComponent.init, "missing page.init"
		Assert pageComponent.suggestClose, "missing page.suggestClose"
		Assert pageComponent.deinit, "missing page.deinit"
		if global.ActiveSession
			Assert pageComponent.getPageListeners, "missing page.getPageListeners"

		# Are we in the middle of a hot code replace for this page?
		hcrState = global.HCRSavedState[win.location.href]
		if hcrState
			try
				# Inject state from prior to reload
				HotCodeReplace.restoreSnapshot pageComponent, hcrState
			catch err
				# HCR is risky, so hope that it wasn't too bad
				console.error "HCR: #{err.toString()}"

			delete global.HCRSavedState[win.location.href]
		else
			# No HCR, so just a normal init
			pageComponent.init()

		# Listen for close button or Alt-F4
		nwWin.on 'close', onWindowCloseEvent

		# Register all listeners if logged in
		if global.ActiveSession
			isLoggedIn = true
			registerPageListeners()

		# Disable context menu
		#win.document.addEventListener 'contextmenu', (event) ->
		#	event.preventDefault()
		#	return false

		# User-Facing Utlities
		devToolsKeyCount = null

		win.document.addEventListener 'keydown', (event) ->
			# Prevent backspace navigation
			if event.which is 8 and event.target.tagName is 'BODY'
				event.preventDefault()
			# TODO: Remove this, since it can't run in production anyway
			# devTools with Ctrl-Shift-J x5
			# if event.ctrlKey and event.shiftKey and event.which is 74
			# 	unless devToolsKeyCount?
			# 		devToolsKeyCount = 0
			# 		setTimeout (->
			# 			devToolsKeyCount = null
			# 		), 2000
			# 	devToolsKeyCount++
			# 	if devToolsKeyCount > 4
			# 		win.nw.Window.get(win).showDevTools()
		, false


		# DevMode Utilities
		if Config.devMode

			# Convenience method for checking React perf
			# Simply call start(), [do action], stop() on the window console
			# TODO
			# Perf is only available with dev build of React (which is no longer loaded via main.html) --
			# will add back in 1.9
			#Perf = React.addons.Perf
			#win.start = Perf.start
			#win.stop = ->
			#	Perf.stop()
			#	Perf.printWasted()

			# Ctrl-Shift-J opens devTools for current window context
			win.document.addEventListener 'keyup', (event) ->
				if event.ctrlKey and event.shiftKey and event.which is 74
					win.nw.Window.get().showDevTools()
			, false

			# Ctrl-Shift-B opens devTools for background window context
			win.document.addEventListener 'keyup', (event) ->
				if event.ctrlKey and event.shiftKey and event.which is 66
					# From https://github.com/nwjs/nw.js/issues/4881
					chrome.developerPrivate.openDevTools({
						renderViewId: -1
						renderProcessId: -1
						extensionId: chrome.runtime.id
					})
			, false

			win.document.addEventListener 'keyup', (event) ->
				# If Ctrl-R
				if event.ctrlKey and (not event.shiftKey) and event.which is 82
					console.log "- - - Hot Code Replace - - -"
					doHotCodeReplace()
			, false

			# Ctrl-F runs a quick CSS refresh
			win.document.addEventListener 'keyup', (event) ->
				if event.ctrlKey and (not event.shiftKey) and event.which is 70
					refreshCSS()
			, false


	doHotCodeReplace = =>
		console.log "Running HCR Reload..."

		# Save the entire page state into a global var
		global.HCRSavedState[win.location.href] = HotCodeReplace.takeSnapshot pageComponent

		# Unregister page listeners
		unregisterPageListeners() if isLoggedIn

		# Unmount components normally, but with no deinit
		ReactDOM.unmountComponentAtNode containerElem

		# Remove window listener (a new one will be added after the reload)
		nwWin.removeListener 'close', onWindowCloseEvent

		# Clear Node.js module cache
		for cacheId of require.cache
			delete require.cache[cacheId]

		# Reload HTML page
		win.location.reload(true)

	refreshCSS = =>
		Fs = require 'fs'
		Stylus = require 'stylus'

		mainStylusCode = Fs.readFileSync './src/main.styl', {encoding: 'utf-8'}

		stylusOpts = {
			filename: './src/main.styl'
			sourcemap: {inline: true}
		}

		Stylus.render mainStylusCode, stylusOpts, (err, compiledCss) ->
			if err
				console.error "Problem compiling CSS:", err
				if err.stack
					console.error err.stack
				return

			# Inject the compiled CSS into the page
			win.document.getElementById('main-css').innerHTML = compiledCss;
			console.info "- - - Refreshed CSS - - -"

	registerPageListeners = =>
		pageListeners = Imm.fromJS(pageComponent.getPageListeners()).entrySeq()
		timeoutListeners = Imm.fromJS(getTimeoutListeners()).entrySeq()

		# EntrySeq list of all listeners combined
		allListeners = pageListeners.concat timeoutListeners

		# Register all listeners
		allListeners.forEach ([name, action]) =>
			global.ActiveSession.persist.eventBus.on name, action

		# Make sure everything is reset
		global.ActiveSession.persist.eventBus.trigger 'timeout:reset'

	unregisterPageListeners = =>
		# Unregister Chokidar
		chokidarListener.close() if chokidarListener?

		# Unregister all page listeners
		allListeners.forEach ([name, action]) =>
			global.ActiveSession.persist.eventBus.off name, action

	# Define the listener here so that it can be removed later
	onWindowCloseEvent = =>
		try
			# Sometimes pageComponent will be undefined during a crash
			pageComponent.suggestClose()
		catch err
			console.warn "Force-closing window..."
			nwWin.close(true)

module.exports = {init}
