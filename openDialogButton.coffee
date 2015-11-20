# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Button that manages layering for opening up a custom dialog

load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	LayeredComponentMixin = require('./layeredComponentMixin').load(win)
	{FaIcon} = require('./utils').load(win)

	OpenDialogButton = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin, LayeredComponentMixin]

		getDefaultProps: ->
			return {
				onSuccess: ->
				data: null
			}

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

			return @props.dialog({
				onClose: =>
					@setState {isOpen: false}
				onCancel: =>
					@setState {isOpen: false}
				onSuccess: (arg) =>
					@props.onSuccess(arg)
					@setState {isOpen: false}
					
				data: @props.data
			})

	return OpenDialogButton

module.exports = {load}