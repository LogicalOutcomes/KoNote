# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# A <textarea> whose height is determined by the height of its content.
# Note: users can add line breaks inside textareas, which may need special
# handling when being displayed.

_ = require 'underscore'

load = (win) ->
	React = win.React
	R = React.DOM

	ExpandingTextArea = React.createFactory React.createClass
		displayName: 'ExpandingTextArea'
		mixins: [React.addons.PureRenderMixin]		

		render: ->
			return R.div({ref: 'outer'},
				R.textarea({
					className: "expandingTextAreaComponent form-control #{@props.className}"
					ref: 'textarea'
					placeholder: @props.placeholder
					onFocus: @props.onFocus
					onClick: @props.onClick
					onChange: @_onChange
					value: @props.value
					disabled: @props.disabled
				})
			)

		componentDidMount: ->
			@_windowResizeListener = _.debounce =>
				@_resize()
			, 50 # milliseconds

			win.addEventListener 'resize', @_windowResizeListener

			@_resize()

		componentWillUnmount: ->
			win.removeEventListener 'resize', @_windowResizeListener

		_resize: ->
			textareaDom = @refs.textarea
			outerDom = @refs.outer
			return unless textareaDom? and outerDom?

			# Hold outer div to current height
			# This presents the scroll position from being lost when the textarea is set to zero
			outerDom.style.height = outerDom.clientHeight + 'px'

			# Reset height to 0
			textareaDom.style.height = '0px'

			# Calculate new height
			minimumHeight = 54 # pixels
			scrollableAreaHeight = textareaDom.scrollHeight
			scrollableAreaHeight += 2 # to prevent scrollbar
			newHeight = Math.max minimumHeight, scrollableAreaHeight
			textareaDom.style.height = newHeight + 'px'

			# Allow outer div to resize to new height
			outerDom.style.height = 'auto'

		_onChange: (event) ->
			@_resize()
			@props.onChange event

	return ExpandingTextArea

module.exports = {load}
