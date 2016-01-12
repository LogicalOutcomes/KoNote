# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# A good-looking loading animation.
# Also provides an overlay mode that blocks the user from accessing the UI
# while the animation is visible.

load = (win) ->
	React = win.React
	R = React.DOM
	{showWhen} = require('./utils').load(win)

	Spinner = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		componentDidChange: (oldProps, oldState) ->
			# Inform console about loading progress
			if oldProps.message isnt @props.message
				console.log "Message:", @props.message

			if oldProps.percent isnt @props.percent
				console.log "Percent", @props.percent + "%"

		render: ->
			spinner = R.div({
				className: [
					"spinnerComponent"
					'animated fadeOut' if @props.percent? and @props.percent >= 100
					showWhen @props.isVisible
				].join ' '
			},
				R.div({
					className: 'inner'
				},
					R.div({className: 'container container1'},
						R.div({className: 'circle circle1'})
						R.div({className: 'circle circle2'})
						R.div({className: 'circle circle3'})
						R.div({className: 'circle circle4'})
					)
					R.div({className: 'container container2'},
						R.div({className: 'circle circle1'})
						R.div({className: 'circle circle2'})
						R.div({className: 'circle circle3'})
						R.div({className: 'circle circle4'})
					)
					R.div({className: 'container container3'},
						R.div({className: 'circle circle1'})
						R.div({className: 'circle circle2'})
						R.div({className: 'circle circle3'})
						R.div({className: 'circle circle4'})
					)
				)

				R.div({
					className: [
						'infoContainer'
						# 'animated flash' if @props.percent? and @props.percent >= 100
					].join ' '
				},
					if @props.message?
						R.div({className: 'message'}, @props.message)

					if @props.percent?
						R.div({className: 'progress'}, 
							R.div({
								className: [
									'progress-bar progress-bar-striped active'
									'progress-bar-success' if @props.percent >= 100
								].join ' '
								style: {
									width: @props.percent + "%"
								}
							})
						)
				)				

			)

			unless @props.isOverlay
				return spinner

			return R.div({className: "spinnerOverlay #{showWhen @props.isVisible}"},
				spinner
			)

	return Spinner

module.exports = {load}
