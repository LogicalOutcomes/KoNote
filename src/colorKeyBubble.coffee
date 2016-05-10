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
		displayName: 'ColorKeyBubble'
		mixins: [React.addons.PureRenderMixin]

		componentDidMount: ->
			settings = {}

			if @props.data?
				settings = {
					trigger: 'hover'
					placement: 'right'
					container: 'body'
					title: @props.data.get('name') 
					content: @props.data.get('description')
				}
			else if @props.alreadyInUse
				settings = {
					trigger: 'hover'
					placement: 'top'
					container: 'body'
					title: @props.alreadyInUse.get('name') 
					content: @props.alreadyInUse.get('description')
				}

			if @props.hideContent
				settings.content = settings.title
				delete settings.title

			$(@refs.bubble).popover(settings)

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
