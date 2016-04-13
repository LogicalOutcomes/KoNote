# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

load = (win) ->
	# Libraries from browser context
	$ = win.jQuery
	React = win.React
	R = React.DOM

	{FaIcon} = require('./utils').load(win)

	ColorKeyBubble = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		componentDidMount: ->
			if @props.data?
				$(@refs.bubble).popover {
					trigger: 'hover'
					placement: 'right'
					title: @props.data.get('name') 
					content: @props.data.get('description')
				}
			else if @props.alreadyInUse
				$(@refs.bubble).popover {
					trigger: 'hover'
					placement: 'top'
					title: @props.alreadyInUse.get('name') 
					content: @props.alreadyInUse.get('description')
				}

		render: ->
			colorKeyHex = @props.colorKeyHex or @props.data.get('colorKeyHex')	

			R.div({
				className: 'colorKeyBubble'
				ref: 'bubble'
				key: colorKeyHex
			},
				R.div({					
					className: 'bubbleContents'
					onClick: @props.onClick.bind(null, colorKeyHex) if @props.onClick?
					style: {
						background: colorKeyHex
					}
				},
					if @props.isSelected
						FaIcon('check')
					else if @props.alreadyInUse
						FaIcon('ban')
					else
						FaIcon('check', {
							style:
								visibility: 'hidden'
						})
				)
			)


	return ColorKeyBubble

module.exports = {load}
