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
	
	Config = require('./config')

	CrashHandler = require('./crashHandler').load(win)
	Gui = win.require 'nw.gui'

	nwWin = Gui.Window.get(win)

	# application menu bar required for osx copy-paste functionality
	if process.platform == 'darwin'
		mb = new Gui.Menu({type: 'menubar'})
		mb.createMacBuiltin(Config.productName)
		nwWin.menu = mb

	# Handle any uncaught errors.
	# Generally, errors should be passed directly to CrashHandler instead of
	# being thrown so that the error brings down only one window.  Errors that
	# reach this event handler will bring down the entire application, which is
	# usually less desirable.
	process.on 'uncaughtException', (err) ->
		CrashHandler.handle err

	win.jQuery ->
		# Set up keyboard shortcuts
		win.document.addEventListener 'keyup', (event) ->
			# If Ctrl-Shift-J
			if event.ctrlKey and event.shiftKey and event.which is 74
				Gui.Window.get(win).showDevTools()
		, false
		win.document.addEventListener 'keyup', (event) ->
			# If Ctrl-R
			if event.ctrlKey and (not event.shiftKey) and event.which is 82
				# Clear Node.js module cache
				for cacheId of require.cache
					delete require.cache[cacheId]

				# Reload HTML page
				win.location.reload(true)
		, false

		# Pull any parameters out of the URL
		urlParams = QueryString.parse win.location.search.substr(1)

		# Decide what page to render based on the page parameter
		# URL would look something like `.../main.html?page=client`
		pageModulePath = pageModulePathsById[urlParams.page or defaultPageId]

		# Load the page module
		pageComponentClass = require(pageModulePath).load(win, urlParams)

		# Render page in window
		pageComponent = win.React.render pageComponentClass({
			closeWindow: =>
				nwWin.close true
			maximizeWindow: =>
				nwWin.maximize()
			setWindowTitle: (newTitle) =>
				nwWin.title = newTitle
		}), win.document.getElementById('container')

		# Make sure up front that this page has the required methods
		Assert pageComponent.suggestClose, "mising page.suggestClose"
		Assert pageComponent.close, "missing page.close"

		# Listen for close button or Alt-F4
		nwWin.on 'close', =>
			pageComponent.suggestClose()
			return

module.exports = {init}
