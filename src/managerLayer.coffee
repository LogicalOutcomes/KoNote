# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Layer that switches between administrative tabs

load = (win) ->
	# Libraries from browser context
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	ProgramManagerTab = require('./programManagerTab').load(win)
	AccountManagerTab = require('./accountManagerTab').load(win)
	ExportManagerTab = require('./exportManagerTab').load(win)
	MyAccountManagerTab = require('./myAccountManagerTab').load(win)
	EventTypeManagerTab = require('./eventTypeManagerTab').load(win)
	MetricDefinitionManagerTab = require('./metricDefinitionManagerTab').load(win)
	PlanTemplateManagerTab = require('./planTemplateManagerTab').load(win)

	ManagerLayer = React.createFactory React.createClass
		displayName: 'ManagerLayer'
		mixins: [React.addons.PureRenderMixin]

		render: ->
			Module = switch @props.name
				when 'programManagerTab'
					ProgramManagerTab
				when 'accountManagerTab'
					AccountManagerTab
				when 'exportManagerTab'
					ExportManagerTab
				when 'myAccountManagerTab'
					MyAccountManagerTab
				when 'eventTypeManagerTab'
					EventTypeManagerTab
				when 'metricDefinitionManagerTab'
					MetricDefinitionManagerTab
				when 'planTemplateManagerTab'
					PlanTemplateManagerTab

			return R.div({className: 'managerLayer'},
				R.div({className: 'managerLayerContainer'},
					Module @props
				)
			)

	return ManagerLayer

module.exports = {load}