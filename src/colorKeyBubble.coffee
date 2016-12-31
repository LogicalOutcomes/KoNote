# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Generic bubble component to show color/details for programs, eventTypes, etc

load = (win) ->
	# Libraries from browser context
	$ = win.jQuery
	React = win.React
	R = React.DOM

	{FaIcon} = require('./utils').load(win)


	ColorKeyBubble = React.createFactory React.createClass
		displayName: 'ColorKeyBubble'
		mixins: [React.addons.PureRenderMixin]

		propTypes: {
			colorKeyHex: React.PropTypes.string
			popover: React.PropTypes.shape {
				placement: React.PropTypes.oneOf ['left', 'right', 'top', 'bottom']
				container: React.PropTypes.string
				title: React.PropTypes.string
				content: React.PropTypes.string
			}
			icon: React.PropTypes.oneOf ['ban', 'check']
			onClick: React.PropTypes.func
		}

		getDefaultProps: -> {
			onClick: ->
		}

		componentDidMount: ->
			popoverOptions = @props.popover
			return unless popoverOptions?

			$(@refs.bubble).popover {
				trigger: 'hover'
				placement: popoverOptions.placement or 'right'
				container: popoverOptions.container or 'body'
				title: popoverOptions.title
				content: popoverOptions.content
			}

		render: ->
			{onClick, colorKeyHex, icon} = @props

			R.div({className: 'colorKeyBubble'},
				R.div({
					ref: 'bubble'
					className: [
						'bubbleContents'
						'empty' unless colorKeyHex
					].join ' '
					onClick
					style: {
						background: colorKeyHex
						borderColor: colorKeyHex
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
