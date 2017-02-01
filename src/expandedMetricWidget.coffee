# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# A component for indicating the presence or displaying the value of a metric.

load = (win) ->
	$ = win.jQuery
	React = win.React
	R = React.DOM
	ReactDOMServer = win.ReactDOMServer

	{FaIcon, renderLineBreaks, showWhen} = require('./utils').load(win)


	ExpandedMetricWidget = React.createFactory React.createClass
		displayName: 'MetricWidget'
		mixins: [React.addons.PureRenderMixin]

		render: ->
			return R.div({className:'expandedMetricWidget'},
				R.div({className: 'name', ref: 'name'},
					FaIcon 'line-chart'
					' '
					@props.name
				)

				R.div({className: 'definition', ref: 'definition'},
					@props.definition
				)
			)

	return ExpandedMetricWidget


module.exports = {load}