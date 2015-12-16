# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Layer that siwthces between administrative tabs

load = (win) ->
	# Libraries from browser context
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	ClientFileManagerTab = require('./clientFileManagerTab').load(win)
	ProgramManagerTab = require('./programManagerTab').load(win)
	AccountManagerTab = require('./accountManagerTab').load(win)
	ExportManagerTab = require('./exportManagerTab').load(win)

	{FaIcon} = require('./utils').load(win)

	ManagerLayer = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		render: ->
			Module = switch @props.name
				when 'clientFileManagerTab'
					ClientFileManagerTab
				when 'programManagerTab'
					ProgramManagerTab
				when 'accountManagerTab'
					AccountManagerTab
				when 'exportManagerTab'
					ExportManagerTab

			return R.div({className: 'managerLayer'},
				R.div({className: 'managerLayerContainer'},
					Module @props
				)
			)

	return ManagerLayer

module.exports = {load}