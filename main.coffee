# Here, we kick off the appropriate page rendering code based on what page ID
# is specified in the URL.
#
# Special care is taken to provide the correct "window" object.  JS code that
# has been require()'d can't rely on `window` being set to the correct object.
# It seems that only code that was included via a <script> tag can rely on
# `window` being set correctly.

# ES6 polyfills
# These can be removed once we're back to NW.js 0.12+
require 'string.prototype.endswith'
require 'string.prototype.includes'
require 'string.prototype.startswith'

defaultPageId = 'login'
pageModulePathsById = {
	login: './loginPage'
	clientSelection: './clientSelectionPage'
	clientFile: './clientFilePage'
	newProgNote: './newProgNotePage'
	printPreview: './printPreviewPage'
}

init = (win) ->
	Assert = require 'assert'
	Backbone = require 'backbone'
	QueryString = require 'querystring'
	Imm = require 'immutable'
	
	Config = require('./config')

	document = win.document
	React = win.React

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

	# application menu bar required for osx copy-paste functionality
	if process.platform == 'darwin'
		mb = new Gui.Menu({type: 'menubar'})
		mb.createMacBuiltin(Config.productName)
		Gui.Window.get().menu = mb

	containerElem = document.getElementById('container')
	pageComponent = null
	pageListeners = null

	process.nextTick =>
		renderPage()
		initPage()

	renderPage = =>		
		# Pull any parameters out of the URL
		urlParams = QueryString.parse win.location.search.substr(1)

		# Decide what page to render based on the page parameter
		# URL would look something like `.../main.html?page=client`
		pageModulePath = pageModulePathsById[urlParams.page or defaultPageId]

		# Load the page module
		pageComponentClass = require(pageModulePath).load(win, urlParams)			

		# Render page in window
		pageComponent = React.render pageComponentClass({			
			closeWindow: =>
				pageComponent.deinit()
				unregisterListeners() if global.ActiveSession and pageListeners
				React.unmountComponentAtNode containerElem

				nwWin.close true

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

		# Are we in the middle of a hot code replace?
		if global.HCRSavedState?
			try
				# Inject state from prior to reload
				HotCodeReplace.restoreSnapshot pageComponent, global.HCRSavedState
			catch err
				# HCR is risky, so hope that it wasn't too bad
				console.error "HCR: #{err.toString()}"

			global.HCRSavedState = null
		else
			# No HCR, so just a normal init
			pageComponent.init()

		# Listen for close button or Alt-F4
		nwWin.on 'close', onWindowCloseEvent

		# Register all listeners if logged in
		registerListeners() if global.ActiveSession

		# Set up keyboard shortcuts
		win.document.addEventListener 'keyup', (event) ->
			# If Ctrl-Shift-J
			if event.ctrlKey and event.shiftKey and event.which is 74
				Gui.Window.get(win).showDevTools()
		, false
		win.document.addEventListener 'keyup', (event) ->
			# If Ctrl-R
			if event.ctrlKey and (not event.shiftKey) and event.which is 82
				doHotCodeReplace()
		, false

	doHotCodeReplace = =>
		# Save the entire page state into a global var
		global.HCRSavedState = HotCodeReplace.takeSnapshot pageComponent

		# Unmount components normally, but with no deinit
		React.unmountComponentAtNode containerElem

		# Remove window listener (a new one will be added after the reload)
		nwWin.removeListener 'close', onWindowCloseEvent

		# Clear Node.js module cache
		for cacheId of require.cache
			delete require.cache[cacheId]

		# Reload HTML page
		win.location.reload(true)

	registerListeners = =>
		# Register listeners from internal page component
		pageListeners = Imm.fromJS pageComponent.getPageListeners()
		.mergeDeep getTimeoutListeners() # and merge in timeout listeners

		pageListeners.forEach (action, name) =>
			# console.log "Registered listener:", name
			global.ActiveSession.persist.eventBus.on name, action

	unregisterListeners = =>
		# Unregister page listeners
		pageListeners.forEach (action, name) =>
			# console.log "Unregistered listener:", name
			global.ActiveSession.persist.eventBus.stopListening name, action

	# Define the listener here so that it can be removed later
	onWindowCloseEvent = =>
		pageComponent.suggestClose()

module.exports = {init}
