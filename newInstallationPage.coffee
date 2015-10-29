# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

Config = require './config'

load = (win) ->
	# Libraries from browser context
	$ = win.jQuery
	React = win.React
	R = React.DOM

	{FaIcon} = require('./utils').load(win)

	NewInstallationPage = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		stuff: ->
			(cb) =>
				@setState {isLoading: true}
				Persist.setUpDataDirectory Config.dataDirectory, (err) =>
					@setState {isLoading: false}

					if err
						cb err
						return

					cb()
			(cb) =>
				@setState {isLoading: true}
				Persist.Users.Account.setUp Config.dataDirectory, (err, result) =>
					@setState {isLoading: false}

					if err
						cb err
						return

					systemAccount = result
					cb()
			(cb) =>
				@setState {isLoading: true}
				Persist.Users.Account.create systemAccount, 'admin', adminPassword, 'admin', (err) =>
					@setState {isLoading: false}

					if err
						if err instanceof Persist.Users.UserNameTakenError
							Bootbox.alert "An admin #{Term 'user account'} already exists."
							process.exit(1)
							return

						cb err
						return

					cb()

		render: ->
			return R.div({id: 'newInstallationPage'},
				R.section({},
					R.div({id: 'brandContainer'},
						R.div({},
							R.img({
								id: 'logoImage'
								src: './assets/brand/logo.png'
							})
							R.div({id: 'version'}, "v1.4.0 (Beta)")
						)						
					)
					R.div({id: 'contentContainer'}
						R.h1({}, "You're almost done!")
						R.p({}, "Welcome to the KoNote beta program.")
						R.p({}, "Let's set you up with an \"admin\" account, and launch your new database.")
						R.div({className: 'btn-toolbar'},
							R.button({
								className: 'btn btn-lg btn-default'
							}, 
								"Help"
							)
							R.button({
								className: 'btn btn-lg btn-success'
							}, 
								"Create Admin Account"
								FaIcon('arrow-right')
							)
						)
					)					
				)
			)

	return NewInstallationPage

module.exports = {load}