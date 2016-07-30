# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

Fs = require 'fs'
Async = require 'async'
Rimraf = require 'rimraf'

Config = require './config'
Persist = require './persist'
Atomic = require './persist/atomic'

yauzl = require('yauzl');
path = require("path")
mkdirp = require("mkdirp")


load = (win) ->
	# Libraries from browser context
	$ = win.jQuery
	React = win.React
	R = React.DOM
	Bootbox = win.bootbox

	Gui = win.require 'nw.gui'
	Window = Gui.Window.get()

	Spinner = require('./spinner').load(win)
	CrashHandler = require('./crashHandler').load(win)
	{FaIcon} = require('./utils').load(win)


	NewInstallationPage = React.createFactory React.createClass
		displayName: 'NewInstallationPage'
		mixins: [React.addons.PureRenderMixin]

		init: ->			
			@_testDataDirectory()
			@_testLocalWritePermissions()

		deinit: (cb=(->)) ->
			cb()

		componentDidMount: ->
			Window.show()
			Window.focus()

		suggestClose: ->
			@refs.ui.suggestClose()

		_testDataDirectory: ->
			dataDirectory = Config.dataDirectory

			# Ensure a non-standard dataDirectory path actually exists
			if dataDirectory isnt 'data' and not Fs.existsSync(dataDirectory)
				Bootbox.alert {
					title: "Database folder not found"
					message: """
						The destination folder specified for the database installation
						can not be found on the file system. 
						Please check the 'dataDirectory' path in your configuration file.
					"""
					callback: =>
						process.exit(1)
				}
			else
				console.log "Data directory is valid!"

		_testLocalWritePermissions: ->
			fileTestPath = 'writeFileTest.txt'
			fileTestString = "Hello World!"

			Async.series [
				(cb) => Fs.writeFile fileTestPath, fileTestString, cb
				(cb) => Fs.unlink fileTestPath, cb
			], (err) =>

				if err and err.code is 'EROFS'
					additionalMessage = unless process.platform is 'darwin' then "" else
						"Please make sure you have dragged #{Config.productName} into
						your Applications folder."

					Bootbox.alert """
						ERROR: '#{err.code}'.
						Unable to write to the local directory.
						#{additionalMessage}
					""", @props.closeWindow

					console.error "Unable to write to local directory:", err
					return

				else if err
					Bootbox.alert """
						ERROR: '#{err.code}'.
						Please contact #{Config.productName} technical support.
					""", @props.closeWindow

					console.error "Local directory write test error:", err
					return

				# Test successful
				console.log "Local directory is writeable!"


		render: ->
			return NewInstallationPageUi({
				ref: 'ui'
				closeWindow: @props.closeWindow
			})


	NewInstallationPageUi = React.createFactory React.createClass
		displayName: 'NewInstallationPageUi'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				openTab: 'index'

				isLoading: null
				installProgress: {
					message: null
					percent: null
				}

				password: ''
				passwordConfirmation: ''

				authkey: ''
			}

		componentDidUpdate: (oldProps, oldState) ->
			# Detech tab change to createAdmin
			if @state.openTab isnt oldState.openTab and @state.openTab is 'createAdmin'
				# Focus first password input
				$password = $(@refs.password)
				$password.focus()

		suggestClose: ->
			if global.isSetUp
				@props.closeWindow()
			else
				Bootbox.dialog {
					message: "Are you sure you want to cancel installation?"
					buttons: {
						cancel: {
							label: "No"
							className: 'btn-default'							
						}
						discard: {
							label: "Yes"
							className: 'btn-primary'
							callback: =>
								@props.closeWindow()
						}
					}
				}

		render: ->
			if @state.isLoading
				return R.div({id: 'newInstallationPage'},
					Spinner {
						isOverlay: true
						isVisible: true
						message: @state.installProgress.message
						percent: @state.installProgress.percent
					}
				)

			return R.div({
				id: 'newInstallationPage'
				className: 'animated fadeIn'
			},
				R.section({},
					R.div({
						id: 'brandContainer'
						className: 'animated fadeInDown'
					},
						R.div({},
							R.img({
								id: 'logoImage'
								src: './assets/brand/logo.png'
							})
							R.div({id: 'version'}, "v#{Config.version}")
						)						
					)
					R.div({
						id: 'contentContainer'
						# className: 'animated fadeInUp'
					},
						(switch @state.openTab
							when 'index'
								R.div({ref: 'index'},
									# hidden input for opening backup zip
									R.input({
										ref: 'nwbrowse'
										className: 'hidden'
										type: 'file'
									})
									R.h2({}, "Thank you for trying the #{Config.productName} beta!")
									R.p({}, "To get started, let's set up your user account...")
									R.br({})
									R.div({className: 'btn-toolbar'},
										R.button({
											className: 'btn btn-lg btn-default'
											onClick: @_import.bind null, {
												extension: 'zip'
												onImport: @_confirmRestore
											}
										}, 
											"Restore Backup"
											FaIcon('upload right-side')
										)
										R.button({
											className: 'btn btn-lg btn-default'
											onClick: @_switchTab.bind null, 'createAdmin'
										}, 
											"Create Admin Account"
											FaIcon('arrow-right right-side')
										)
									)
									R.div({className: 'btn-toolbar'},
										R.br({})
										R.button({
											className: 'btn btn-lg btn-success'
											onClick: @_switchTab.bind null, 'joinCloud'
										}, 
											"Use a KoNote Cloud account"
											FaIcon('cloud right-side')
										)
									)
								)
							when 'joinCloud'
								R.div({ref: 'joinCloud'},
									R.p({}, "To continue, please enter your authentication key:")
									R.div({},
										R.textarea({
											style: {minWidth: 600, minHeight: 200}
											ref: 'authkey'
											id: 'authkey'
											className: 'form-control'
											type: 'text'
											placeholder: "Paste your private key here. The first line should be: ------BEGIN RSA PRIVATE KEY------"
											value: @state.authkey
											onChange: @_updateAuthkey
										})
									)
									R.div({className: 'btn-toolbar'},
										R.br({})
										R.button({
											className: 'btn btn-lg btn-default'
											onClick: @_switchTab.bind null, 'index'
										}, 
											"Cancel"
										)
										R.button({
											className: 'btn btn-lg btn-success'
											onClick: @_syncCloud
										},
											"Connect"
											FaIcon('arrow-right')
										)
									)
								)
							when 'createAdmin'
								R.div({ref: 'createAdmin'},
									R.h2({}, "Your username will be \"admin\"")
									R.p({}, 								
										"Please choose a password"
									)
									R.div({
										id: 'passwordFields'
										className: 'row-fluid'
									},
										R.div({className: 'col-md-6'},
											R.div({
												className: [
													'form-group has-feedback'
													'has-success' if @state.password.length > 0
												].join ' '
											},
												R.label({
													htmlFor: 'password'
												}, "Password")
												R.input({
													ref: 'password'
													id: 'password'
													className: 'form-control'
													type: 'password'											
													placeholder: "Set Password"
													value: @state.password
													onChange: @_updatePassword											
												})
												R.span({className: 'glyphicon glyphicon-ok form-control-feedback'})
											)
										)
										R.div({className: 'col-md-6'},
											R.div({
												className: [
													'form-group has-feedback'
													if @_passwordsMatch()
														'has-success'
													else if @state.passwordConfirmation.length > 0
														'has-error'
												].join ' '
											},
												R.label({
													htmlFor: 'passwordConfirmation'
												}, "Confirm password")
												R.input({
													ref: 'passwordConfirmation'
													id: 'passwordConfirmation'
													className: 'form-control'
													type: 'password'											
													placeholder: "Password again"
													value: @state.passwordConfirmation
													onChange: @_updatePasswordConfirmation
												})
												R.span({className: 'glyphicon glyphicon-ok form-control-feedback'})
											)
										)
									)
									R.div({className: 'btn-toolbar'},
										R.button({
											className: [
												'btn btn-lg btn-success'
												'animated pulse' if @_passwordsMatch()
											].join ' '
											disabled: not @_passwordsMatch()
											onClick: @_install
										},
											"Create Account"
											FaIcon('check') if @_passwordsMatch()
										)
									)
								)

						)
					)
					R.div({
						id: 'helpContainer'
						className: 'animated fadeIn'
					}, 
						"Contact us:"						
						R.a({
							href: "#"
							onClick: @_copyHelpEmail.bind null, Config.supportEmailAddress
						},
							Config.supportEmailAddress
						)
					)
				)
			)

		_import: ({extension, onImport}) ->
			# Configures hidden file inputs with custom attributes, and clicks it
			$nwbrowse = $(@refs.nwbrowse)
			$nwbrowse
			.off()
			.attr('accept', ".#{extension}")			
			.on('change', (event) => onImport event.target.value)
			.click()
	
		_confirmRestore: (backupfile) ->
			Bootbox.confirm {
				title: "Warning"
				message: "Restoring from a backup will OVERWRITE ANY EXISTING DATA. Are you sure you want to continue?"
				callback: (confirmed) =>
					unless confirmed
						return
					@setState {
						isLoading: true
						installProgress: {message: "Restoring data file. This may take some time..."}
					}
					@_restoreBackup(backupfile)
			}

		_restoreBackup: (backupfile) ->
			dataDir = Config.dataDirectory
			backupDir = dataDir + '_tmp_backup-' + Date.now()
			tmpDir = dataDir + '_tmp_import'
			atomicOp = null
			
			Async.series [
				(cb) =>
					unless Fs.existsSync(Config.dataDirectory)
						mkdirp Config.dataDirectory, (err) =>
							if err
								cb err
								return
					Fs.rename dataDir, backupDir, (err) =>
						if err
							@setState {
								isLoading: false
							}
							Bootbox.alert {
								title: "Error"
								message: "Unable to create temp data directory. Import aborted."
							}
							cb err
							return
						cb()

				(cb) =>
					Atomic.writeDirectoryNormally dataDir, tmpDir, (err, op) =>
						if err 
							if err instanceof Persist.IOError and err.cause.code is 'EEXIST'
							# previous import data still exists: overwrite
								Rimraf tmpDir, (err) =>
									if err
										cb err
										return
									@_restoreBackup(backupfile)
								return
							cb err
							return

						# atomic operation
						atomicOp = op
						cb()
				
				(cb) =>
					yauzl.open backupfile, { lazyEntries: true }, (err, zipfile) =>
						if err
							@setState {
								isLoading: false
							}
							Bootbox.alert {
								title: "Error"
								message: "Unable to open zip file. Please check that you have a valid data file."
							}
							cb err
							return
						zipfile.readEntry()
						
						zipfile.on 'entry', (entry) =>
							if /\/$/.test(entry.fileName)
								# directory (filename ends with /)
								mkdirp path.join(tmpDir, entry.fileName), (err) =>
									if err
										cb err
										return
									zipfile.readEntry()
									return
							else
								# file
								zipfile.openReadStream entry, (err, readStream) =>
									if err
										cb err
										return
									readStream.pipe Fs.createWriteStream(path.join(tmpDir, entry.fileName))
									readStream.on 'end', =>
										zipfile.readEntry()
										return
									return
								return
						
						zipfile.on 'close', =>
							# zip extracted; check metadata
							unless Fs.existsSync(path.join(tmpDir, 'version.json')) and Fs.existsSync('./package.json')
								@setState {isLoading: false}
								Bootbox.alert {
									title: "Data Import Failed!"
									message: "Invalid data version. Please ensure you have selected the correct backup file and try again."
								}
								cb err
								return
							cb()
							
				(cb) =>
					appVersion = JSON.parse(Fs.readFileSync('./package.json')).version
					dataVersion = JSON.parse(Fs.readFileSync(path.join(tmpDir, 'version.json'))).dataVersion
					unless appVersion is dataVersion
						@setState {isLoading: false}
						Bootbox.alert {
							title: "Data Import Failed!"
							message: "Invalid data version. Please ensure you have selected the correct backup file and try again."
						}
						cb err
						return
					cb()

				(cb) =>
					atomicOp.commit cb

			], (err) =>
				if err
					@setState {isLoading: false}

					if err instanceof Persist.IOError
						Bootbox.alert {
							title: "Connection Error (IOError)"
							message: "Please check your network connection and try again."
						}
						console.error err
						return

					errCode = [
						err.name or ''
						err.code or err.cause.code
					].join ' '

					Bootbox.alert {
						title: "Data Import Failed"
						message: """
							Sorry, #{Config.productName} was unable to restore the data file.
							Please check your network connection and try again. If the problem persists,
							please contact technical support at <u>#{Config.supportEmailAddress}</u> 
							with the Error Code: \"#{errCode}\".
						"""
					}

					console.error err
					return

				console.log "data import successfull"
				Bootbox.alert {
					title: "Data Import Successful!"
					message: "KoNote will now restart..."
					callback: ->
						global.isSetUp = true
						win.close(true)
				}


		_copyHelpEmail: (emailAddress) ->
			clipboard = Gui.Clipboard.get()
			clipboard.set emailAddress

			Bootbox.alert {
				title: "Copied Support E-mail"
				message: "\"#{emailAddress}\" copied to your clipboard!"
			}

		_updateAuthkey: (event) ->
			@setState {authkey: event.target.value}

		_updatePassword: (event) ->
			@setState {password: event.target.value}

		_updatePasswordConfirmation: (event) ->
			@setState {passwordConfirmation: event.target.value}

		_passwordsMatch: ->
			return @state.password is @state.passwordConfirmation and @state.password.length > 0

		_switchTab: (newTab) ->
			# TODO: Make this some kind of flexible component/mixin
			openTab = @state.openTab
			isIndex = openTab is 'index'
			
			# Animation directions
			offDirection = if isIndex then 'Left' else 'Right'
			onDirection = if isIndex then 'Right' else 'Left'

			# Transition out oldTab
			$oldTab = $(@refs[openTab])
			$oldTab.attr 'class', ('animated fadeOut' + offDirection)

			# Wait (.75 of anim default) and transition in the newTab
			setTimeout(=>
				@setState {openTab: newTab}, =>
					$newTab = $(@refs[newTab])
					$newTab.attr 'class', ('animated fadeIn' + onDirection)
			, 500)

		_updateProgress: (percent, message) ->
			if not percent and not message
				percent = message = null

			@setState {
				isLoading: true
				installProgress: {percent, message}
			}

		_syncCloud: ->
			exec = require('child_process').exec;
			key = @state.authkey

			# write key to user's temp directory
			Fs.writeFile 'authkey', key, (err) =>
				if err
					throw err
				# key requires strict permissions or ssh ignores it
				# unfortunately no cross-platform way to set this
				if process.platform is 'win32'
					user = process.env.username
					console.log user
					changeperm = "icacls authkey /inheritance:r /grant:r #{process.env.username}:(F)"
				else
					changeperm = 'chmod 600 authkey'
				exec changeperm, (err) =>
					if err
						throw err
					Persist.buildDataDirectory Config.dataDirectory, (err) =>
						if err
							throw err
						# pull remote data
						@setState {
							isLoading: true
							installProgress: {message: "Syncing with Cloud (this may take some time)..."}
						}
						Persist.Sync.pull 0, (err) =>
							@setState {isLoading: false}
							if err
								Bootbox.alert {
									title: "Cloud sync failed!"
									message: "Please check your network connection and try again."
								}
								return
							else
								console.log 'sync done'
								Bootbox.alert {
									title: "Cloud sync complete!"
									message: "KoNote will now restart..."
									callback: =>
										global.isSetUp = true
										win.close(true)
									}
							return

		_install: ->
			if @state.password isnt @state.passwordConfirmation
				Bootbox.alert "Passwords do not match"
				return

			systemAccount = null
			adminPassword = @state.password

			destDataDirectoryPath = Config.dataDirectory
			tempDataDirectoryPath = 'data_tmp'

			atomicOp = null
	
			Async.series [
				(cb) =>
					# Write data folder to temporary local directory, before moving to destination
					Atomic.writeDirectoryNormally destDataDirectoryPath, tempDataDirectoryPath, (err, op) =>
						if err 
							# data_tmp folder already exists from a failed install
							if err instanceof Persist.IOError	and err.cause.code is 'EEXIST'
								Bootbox.confirm {
									title: "OK to overwrite previous/pending installation?"
									message: """
										It appears you have data left over from an incomplete installation.
										Would you like to overwrite it?
									"""
									callback: (confirmed) =>
										if confirmed
											# Delete temp directory and start installation over
											Rimraf tempDataDirectoryPath, (err) =>
												if err
													cb err
													return

												@_install()
								}
								return

							cb err
							return

						# Save our atomic operation
						atomicOp = op
						cb()
				(cb) =>
					@_updateProgress 0, "Setting up database..."

					# Build the data directory, with subfolders/collections indicated in dataModels
					Persist.buildDataDirectory tempDataDirectoryPath, (err) =>
						if err
							cb err
							return

						cb()
				(cb) =>					
					@_updateProgress 25, "Generating secure encryption keys (this may take a while...)"
										
					isDone = false
					# Only fires if async setUp
					setTimeout(=>
						unless isDone
							@_updateProgress 50, "Setting up user account system (this may take a while...)"
					, 3000)

					# Generate mock "_system" admin user
					Persist.Users.Account.setUp tempDataDirectoryPath, (err, result) =>
						if err
							cb err
							return

						systemAccount = result
						isDone = true
						cb()
				(cb) =>
					@_updateProgress 75, "Creating your \"admin\" user . . ."
					# Create admin user account using systemAccount
					Persist.Users.Account.create systemAccount, 'admin', adminPassword, 'admin', (err) =>
						if err
							if err instanceof Persist.Users.UserNameTakenError
								Bootbox.alert "An admin #{Term 'user account'} already exists."
								process.exit(1)
								return

							cb err
							return

						cb()
				(cb) =>
					atomicOp.commit cb
			], (err) =>
				if err
					@setState {isLoading: false}

					if err instanceof Persist.IOError
						Bootbox.alert {
							title: "Connection Error (IOError)"
							message: "Please check your network connection and try again."
						}
						console.error err
						return

					errCode = [
						err.name or ''
						err.code or err.cause.code
					].join ' '

					Bootbox.alert {
						title: "Error (#{errCode})"
						message: """
							Sorry, we seem to be having some trouble installing #{Config.productName}.
							Please check your network connection and try again, otherwise contact
							technical support at <u>#{Config.supportEmailAddress}</u> 
							with the Error Code: \"#{errCode}\" .
						"""
					}

					console.error err
					return


				console.log "Successfully installed #{Config.productName}!"
				@_updateProgress 100, "Successfully installed #{Config.productName}!"

				# Allow 1s for success animation before closing
				setTimeout(=>
					global.isSetUp = true
					win.close(true)
				, 1000)



	return NewInstallationPage

module.exports = {load}