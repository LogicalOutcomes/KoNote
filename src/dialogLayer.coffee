# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Wrapper for opening a layered dialog component
# Use @ref to call 'open' method, takes (dialogComponent, props)

# IMPORTANT: Only pass in raw (unfiltered) collection data,
# for example: favour @state.data over table data

_ = require 'underscore'


load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM
	{PropTypes} = React

	LayeredComponentMixin = require('./layeredComponentMixin').load(win)
	{FaIcon} = require('./utils').load(win)


	DialogLayer = React.createFactory React.createClass
		displayName: 'DialogLayer'
		mixins: [React.addons.PureRenderMixin, LayeredComponentMixin]

		getInitialState: ->
			return {
				isOpen: false
				dialogComponent: ->
				dialogProps: {}
			}

		render: -> @props.children

		# Call this method on the 'dialogLayer' ref, props are optional
		open: (dialogComponent, props = {}) ->
			defaultProps = {
				onClose: ->
				onCancel: ->
				onSuccess: ->
			}

			# TODO: Validate props.onClose (etc) is a valid function

			# Override defaults with specified props
			dialogProps = _.extend(defaultProps, props)

			# This triggers renderLayer
			@setState {
				isOpen: true
				dialogComponent
				dialogProps
			}

		renderLayer: ->
			unless @state.isOpen
				return R.div()

			# Wrap dialog methods with close functionality
			# TODO: Wipe the current state clean when closed?
			defaultProps = {
				onClose: (arg) =>
					@state.dialogProps.onClose(arg)
					@setState {isOpen: false}
				onCancel: (arg) =>
					@state.dialogProps.onCancel(arg)
					@setState {isOpen: false}
				onSuccess: (arg) =>
					@state.dialogProps.onSuccess(arg)
					@setState {isOpen: false}
			}

			props = _.extend({}, @state.dialogProps, defaultProps, @props)

			console.log "Final Props:", props

			return @state.dialogComponent(props)

	return DialogLayer

module.exports = {load}
