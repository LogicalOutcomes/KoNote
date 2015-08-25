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
		render: ->
			isVisible = @props.isVisible isnt false

			spinner = R.div({className: "spinnerComponent #{showWhen isVisible}"},
				R.div({className: 'inner'},
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
			)

			unless @props.isOverlay
				return spinner

			return R.div({className: "spinnerOverlay #{showWhen isVisible}"},
				spinner
			)

	return Spinner

module.exports = {load}
