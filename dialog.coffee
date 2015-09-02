# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# A generic dialog component

load = (win) ->
	$ = win.jQuery
	React = win.React
	R = React.DOM
	{FaIcon} = require('./utils').load(win)

	Dialog = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]
		render: ->
			return R.div({
				className: [
					'dialogContainer'
					if @props.containerClasses then @props.containerClasses.join(' ')
				].join(' ')
				onClick: if not @props.disableBackgroundClick then @_onBackgroundClick
			},
				R.div({className: 'dialog panel panel-primary'},
					R.div({className: 'panel-heading'},
						R.h3({className: 'panel-title'}, @props.title)
						R.span({
							className: 'panel-quit'
							onClick: @props.onClose
						}, FaIcon('times'))
					)
					R.div({className: 'panel-body'},
						@props.children
					)
				)
			)
		_onBackgroundClick: (event) ->
			# If click was on background, not the dialog itself
			if event.target.classList.contains 'dialogContainer'
				@props.onClose()

	return Dialog

module.exports = {load}
