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
	{FaIcon} = require('./utils').load(win)

	Spinner = require('./spinner').load(win)

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
			}

		render: ->
			return R.div({
				className: [
					'dialogContainer'
					@props.containerClasses.join(' ')
				].join(' ')
				onClick: unless @props.disableCancel or @props.disableBackgroundClick then @_onBackgroundClick
			},
				Spinner({
					isVisible: @state.isLoading
					isOverlay: true
				})
				R.div({className: 'dialog panel panel-primary animated fadeInUp'},
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

		setIsLoading: (newState) ->
			@setState => {isLoading: newState}

		isLoading: -> @state.isLoading

		_onBackgroundClick: (event) ->
			# If click was on background, not the dialog itself
			if event.target.classList.contains 'dialogContainer'
				@props.onClose()

	return Dialog

module.exports = {load}
