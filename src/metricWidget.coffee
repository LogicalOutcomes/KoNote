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
		# TODO: propTypes

		getDefaultProps: -> {
			tooltipViewport: 'body'
		}

		componentDidMount: ->
			# TODO: Update definition when @props.definition changes
			tooltipContent = R.div({className: 'tooltipContent'},
				renderLineBreaks @props.definition
			)

			$(@refs.name).tooltip {
				html: true
				title: ReactDOMServer.renderToString tooltipContent
				placement: 'auto'
				viewport: {
					selector: @props.tooltipViewport
					padding: 0
				}
			}

		render: ->
			# Here we calculate the width needed for the widget's input and set inline below
			# Note: the added space directly correlates to the padding on .innerValue
			if @props.value?
				inputWidth = (@props.value.length * 10) + 10


			return R.div({
				className: [
					'metricWidget'
					@props.styleClass or ''
				].join ' '
			},
				(if @props.value?
					R.div({className: 'value circle'},
						(if @props.isEditable
							R.input({
								className: 'innerValue'
								style: {width: "#{inputWidth}px"}
								onFocus: @props.onFocus
								value: @props.value
								onChange: @_onChange
								placeholder: '__'
								maxLength: 20
							})
						else
							R.div({className: 'innerValue'},
								@props.value or '--'
							)
						)
					)
				else
					R.div({className: 'icon circle'},
						FaIcon 'line-chart'
					)
				)
				R.div({
					ref: 'name'
					id: @props.id
					className: 'name'
				},
					@props.name
				)
				(if @props.allowDeleting and not @props.isReadOnly
					R.div({className: 'delete', onClick: @props.onDelete},
						FaIcon 'times'
					)
				)
			)

		_onChange: (event) ->
			if @props.onChange
				@props.onChange event.target.value


	return MetricWidget


module.exports = {load}
