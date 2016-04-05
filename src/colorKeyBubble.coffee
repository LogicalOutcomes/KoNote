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

		render: ->
			R.div({
				className: 'colorKeyBubble'
				ref: 'bubble'
				style:
					background: @props.colorKeyHex or @props.data.get('colorKeyHex')
			

			},
				FaIcon('check')


			)



	return ColorKeyBubble

module.exports = {load}
