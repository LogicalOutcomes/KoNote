# A <textarea> whose height is determined by the height of its content.
# Note: users can add line breaks inside textareas, which may need special
# handling when being displayed.

load = (win) ->
	React = win.React
	R = React.DOM

	ExpandingTextArea = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]
		componentDidMount: ->
			@_resize()
		_resize: ->
			textareaDom = @refs.textarea.getDOMNode()

			# Reset height to 0
			textareaDom.style.height = '0px'

			# Calculate new height
			minimumHeight = 54 # pixels
			scrollableAreaHeight = textareaDom.scrollHeight
			scrollableAreaHeight += 2 # to prevent scrollbar
			newHeight = Math.max minimumHeight, scrollableAreaHeight
			textareaDom.style.height = newHeight + 'px'
		render: ->
			return R.textarea({
				className: "expandingTextAreaComponent form-control #{@props.className}"
				ref: 'textarea'
				placeholder: @props.placeholder
				onFocus: @props.onFocus
				onChange: @_onChange
				value: @props.value
			})
		_onChange: (event) ->
			@_resize()
			@props.onChange event

	return ExpandingTextArea

module.exports = {load}
