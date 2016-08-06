# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

load = (win) ->
	# Libraries from browser context
	$ = win.jQuery
	React = win.React
	{PropTypes} = React
	R = React.DOM

	{FaIcon} = require('./utils').load(win)

	ColorKeyBubble = React.createFactory React.createClass
		displayName: 'ColorKeyBubble'
		mixins: [React.addons.PureRenderMixin]

		propTypes: {
			colorKeyHex: PropTypes.string
			popover: PropTypes.shape {
				placement: PropTypes.oneOf ['left', 'right', 'top', 'bottom']
				container: PropTypes.string
				title: PropTypes.string
				content: PropTypes.string
			}
			icon: PropTypes.oneOf ['ban', 'check']
			onClick: PropTypes.func
		}

		getDefaultProps: ->
			return {
				onClick: ->
			}

		componentDidMount: ->
			popoverOptions = @props.popover
			return unless popoverOptions?

			defaultOptions = {
				placement: 'right'
				container: 'body'
			}

			$(@refs.bubble).popover {
				trigger: 'hover'
				placement: popoverOptions.placement or defaultOptions.placement
				container: popoverOptions.container or defaultOptions.container
				title: popoverOptions.title
				content: popoverOptions.content
			}

		render: ->
			{onClick, colorKeyHex, icon} = @props

			R.div({
				className: 'colorKeyBubble'
			},
				R.div({
					ref: 'bubble'
					className: [
						'bubbleContents'
						'empty' unless colorKeyHex
					].join ' '
					onClick
					style: {
						background: colorKeyHex
					}
				},
					# Invisible 'check' icon for sake of display consistency
					FaIcon(icon or 'check', {
						style:
							visibility: 'hidden' unless icon
					})
				)
			)


	return ColorKeyBubble

module.exports = {load}
