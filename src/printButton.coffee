# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

load = (win) ->
	$ = win.jQuery
	React = win.React
	R = React.DOM
	WithTooltip = require('./withTooltip').load(win)
	{FaIcon, openWindow, showWhen} = require('./utils').load(win)

	PrintButton = React.createFactory React.createClass
		displayName: 'PrintButton'
		mixins: [React.addons.PureRenderMixin]

		getDefaultProps: ->
			return {
				tooltip: {
					show: false
					placement: 'top'
					title: "Print"
				}
			}

		render: ->
			return WithTooltip({
				showTooltip: @props.tooltip.show
				placement: @props.tooltip.placement
				title: @props.tooltip.title
			},
				R.a({
					className: [
						'printButton'
						'disabled' if @props.disabled
					].join ' '
					onClick: @_print
					ref: 'printButton'
				},
					R.span({}, if not @props.iconOnly then "Print")
					FaIcon('print')
				)
			)

		_print: ->
			openWindow {
				page: 'printPreview'
				dataSet: JSON.stringify(@props.dataSet)
			}

	return PrintButton

module.exports = {load}
