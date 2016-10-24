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

			return R.span({
				className: [
					'metricWidget'
					@props.styleClass or ''
				].join ' '
			},
				(if @props.value?
					if typeof @props.value in ['string', 'number']
						R.input({
							className: 'value circle'
							onFocus: @props.onFocus
							value: @props.value
							onChange: @_onChange
							placeholder: if @props.isEditable then '__' else '--'
							disabled: not @props.isEditable
						})
					else
						R.div({className: 'value circle'}, @props.value)
				else
					R.div({className: 'icon circle'},
						FaIcon 'line-chart'
					)
				)
				R.div({className: 'name', ref: 'name'},
					@props.name
				)
				(if @props.allowDeleting and not @props.isReadOnly
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
