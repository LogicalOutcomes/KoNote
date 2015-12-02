# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Button that manages layering for opening up a custom dialog
_ = require 'underscore'

load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	LayeredComponentMixin = require('./layeredComponentMixin').load(win)
	{FaIcon} = require('./utils').load(win)

	OpenDialogButton = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin, LayeredComponentMixin]

		getInitialState: ->
			return {
				isOpen: false
			}

		render: ->
			return R.button({
				className: @props.className
				onClick: @_openDialog
			},
				@props.text
				FaIcon(@props.icon)
			)

		_openDialog: ->
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

	return OpenDialogButton

module.exports = {load}