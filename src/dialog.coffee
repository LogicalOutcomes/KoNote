# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# A generic dialog component

# Props:
# 	containerClasses: []
# 	disableBackgroundClick: boolean
# 	disableCancel: boolean

load = (win) ->
	$ = win.jQuery
	React = win.React
	R = React.DOM

	Spinner = require('./spinner').load(win)
	{FaIcon} = require('./utils').load(win)

	Dialog = React.createFactory React.createClass
		displayName: 'Dialog'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				isLoading: false
			}

		getDefaultProps: ->
			return {
				containerClasses: []
				onClose: ->
				disableCancel: false
			}

		propTypes: {
			containerClasses: React.PropTypes.array
			onClose: React.PropTypes.func
			disableCancel: React.PropTypes.bool
		}

		render: ->
			return R.div({
				className: [
					'dialogContainer'
					@props.containerClasses.join(' ')
				].join(' ')
			},
				Spinner({
					isVisible: @state.isLoading
					isOverlay: true
				})
				R.div({className: 'dialog panel panel-primary animated fadeIn'},
					R.div({className: 'panel-heading'},
						R.h3({className: 'panel-title'}, @props.title)
						(unless @props.disableCancel
							R.span({
								className: 'panel-quit'
								onClick: @props.onClose
							}, FaIcon('times'))
						)
					)
					R.div({className: 'panel-body'},
						@props.children
					)
				)
			)

		setIsLoading: (isLoading) ->
			@setState -> {isLoading}

		isLoading: -> @state.isLoading

	return Dialog

module.exports = {load}
