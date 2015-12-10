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
		mixins: [React.addons.PureRenderMixin, LayeredComponentMixin]

		getInitialState: ->
			return {
				isOpen: false
			}

		render: ->
			return R.a({
				className: @props.className
				onClick: @_openDialog
			},
				@props.children
			)

		_openDialog: (event) ->
			event.preventDefault()

			@setState {isOpen: true}

		renderLayer: ->
			unless @state.isOpen
				return R.div()

			defaultProps = {
				onClose: =>
					@setState {isOpen: false}
				onCancel: =>
					@setState {isOpen: false}
				onSuccess: =>
					@setState {isOpen: false}
			}

			props = _.extend(defaultProps, @props)

			return @props.dialog(props)

	return OpenDialogLink

module.exports = {load}
