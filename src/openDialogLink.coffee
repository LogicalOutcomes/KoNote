# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Link that manages layering for opening up a custom dialog.
# This component wraps around whatever you want to be clickable.
# See also: openDialogButton
_ = require 'underscore'

load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	LayeredComponentMixin = require('./layeredComponentMixin').load(win)
	{FaIcon} = require('./utils').load(win)

	OpenDialogLink = React.createFactory React.createClass
		displayName: 'OpenDialogLink'
		mixins: [React.addons.PureRenderMixin, LayeredComponentMixin]

		getInitialState: -> {
			isOpen: false
		}

		getDefaultProps: -> {
				className: ''
				onClose: ->
				onCancel: ->
				onSuccess: ->
		}

		render: ->
			return R.div({
				className: @props.className
				onClick: @open
				disabled: @props.disabled
			},
				@props.children
			)

		open: (event) ->
			event.preventDefault()

			if @props.disabled is false or @props.disabled is undefined
				@setState {isOpen: true}

		renderLayer: ->
			unless @state.isOpen
				return R.div()

			# Runs whatever prop function first, then closes the dialog
			defaultProps = {
				onClose: (arg) =>
					@props.onClose(arg)
					@setState {isOpen: false}
				onCancel: (arg) =>
					@props.onCancel(arg)
					@setState {isOpen: false}
				onSuccess: (arg) =>
					@props.onSuccess(arg)
					@setState {isOpen: false}
			}

			props = _.extend({}, @props, defaultProps)

			return @props.dialog(props)

	return OpenDialogLink

module.exports = {load}
