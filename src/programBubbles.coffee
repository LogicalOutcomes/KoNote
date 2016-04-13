# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

load = (win) ->
	# Libraries from browser context
	React = win.React
	R = React.DOM

	ColorKeyBubble = require('./colorKeyBubble').load(win)


	ProgramBubbles = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		render: ->
			programs = @props.programs.sortBy (program) -> program.get('name').toLowerCase()

			R.div({className: 'programBubbles'}, 
				programs.map (program) -> 
					ColorKeyBubble({
						data: program
						key: program.get('id')
					})
			)

	return ProgramBubbles

module.exports = {load}
