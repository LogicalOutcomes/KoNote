# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Button component to open PrintPreviewPage window with @props.dataSet

load = (win) ->
	$ = win.jQuery
	React = win.React
	R = React.DOM

	WithTooltip = require('./withTooltip').load(win)
	{FaIcon, openWindow, showWhen} = require('./utils').load(win)


	PrintButton = React.createFactory React.createClass
		displayName: 'PrintButton'
		mixins: [React.addons.PureRenderMixin]
		# TODO: propTypes

		getDefaultProps: ->
			return {
				tooltip: {
					show: true
					placement: 'top'
					title: "Print"
				}
				disabled: false
				className: ''
				iconClassName: ''
				labelClassName: ''
			}

		render: ->
			WithTooltip({
				showTooltip: @props.tooltip.show
				placement: @props.tooltip.placement
				title: @props.tooltip.title
			},
				R.button({
					className: [
						'btn printButton'
						@props.className
					].join ' '
					onClick: @_print
					ref: 'printButton'
					disabled: @props.disabled
				},
					FaIcon('print', {className: @props.iconClassName})
					R.span({className: @props.labelClassName},
						"Print" unless @props.iconOnly
					)
				)
			)

		_print: ->
			openWindow {
				page: 'printPreview'
				dataSet: JSON.stringify(@props.dataSet)
			}


	return PrintButton


module.exports = {load}
