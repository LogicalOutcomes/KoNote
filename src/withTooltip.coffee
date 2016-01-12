# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Wrapper component that adds a tooltip using Bootstrap's tooltip feature.

load = (win) ->
	$ = win.jQuery
	React = win.React
	ReactDOM = win.ReactDOM
	{showWhen} = require('./utils').load(win)

	WithTooltip = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		render: ->
			return @props.children

		componentDidMount: ->
			@_configureTooltip()

		componentDidUpdate: ->
			@_configureTooltip()

		_configureTooltip: ->
			if @props.showTooltip is undefined or @props.showTooltip is true
				$(ReactDOM.findDOMNode(@)).tooltip {
					placement: @props.placement
					title: @props.title
				}
			else
				$(ReactDOM.findDOMNode(@)).tooltip 'destroy'

	return WithTooltip

module.exports = {load}
