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

	MetricWidget = React.createFactory React.createClass
		displayName: 'MetricWidget'
		mixins: [React.addons.PureRenderMixin]
		componentDidMount: ->
			tooltipContent = R.div({className: 'tooltipContent'},
				renderLineBreaks @props.definition
			)
			viewport = @props.tooltipViewport || 'body'
			$(@refs.name).tooltip {
				html: true
				title: ReactDOMServer.renderToString tooltipContent
				viewport: {"selector": viewport, "padding": 0 }
			}
		render: ->
			isEditable = @props.isEditable isnt false
			allowDeleting = @props.allowDeleting is true

			return R.div({className: 'metricWidget'},
				(if @props.value?
					R.input({
						className: 'value circle'
						onFocus: @props.onFocus
						value: @props.value
						onChange: @_onChange
						placeholder: (if isEditable
							'__'
						else
							'--'
						)
						disabled: isEditable is false
					})
				else
					R.div({className: 'icon circle'},
						FaIcon 'line-chart'
					)
				)
				R.div({className: 'name', ref: 'name'},
					@props.name
				)
				(if allowDeleting and not @props.isReadOnly
					R.div({className: 'delete', onClick: @props.onDelete},
						FaIcon 'times'
					)
				else
					null
				)
			)
		_onChange: (event) ->
			if @props.onChange
				@props.onChange event.target.value

	return MetricWidget

module.exports = {load}
