# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Wrapper component that adds a tooltip using Bootstrap's tooltip feature.

load = (win) ->
	$ = win.jQuery
	React = win.React
	ReactDOM = win.ReactDOM

	WithTooltip = React.createFactory React.createClass
		displayName: 'WithTooltip'
		mixins: [React.addons.PureRenderMixin]

		getDefaultProps: -> {
			showTooltip: true
			container: false
		}

		componentWillReceiveProps: (newProps) ->
			if @props.title isnt newProps.title and newProps.showTooltip
				$(ReactDOM.findDOMNode(@)).attr('data-original-title', newProps.title)

		render: -> @props.children

		componentDidMount: ->
			@_init()

		componentWillUnmount: ->
			@_destroy()

		_init: ->
			if @props.showTooltip
				$(ReactDOM.findDOMNode(@)).tooltip {
					placement: @props.placement
					title: @props.title
					container: @props.container
				}

		_destroy: ->
			if @props.showTooltip
				$(ReactDOM.findDOMNode(@)).tooltip 'destroy'


	return WithTooltip

module.exports = {load}
