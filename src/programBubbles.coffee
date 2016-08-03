# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

ImmPropTypes = require 'react-immutable-proptypes'

load = (win) ->
	# Libraries from browser context
	React = win.React
	{PropTypes} = React
	R = React.DOM

	ColorKeyBubble = require('./colorKeyBubble').load(win)


	ProgramBubbles = React.createFactory React.createClass
		displayName: 'ProgramBubbles'
		mixins: [React.addons.PureRenderMixin]

		propTypes: {
			programs: ImmPropTypes.list.isRequired
		}

		render: ->
			programs = @props.programs.sortBy (program) -> program.get('name').toLowerCase()

			R.div({className: 'programBubbles'},
				(programs.map (program) ->
					ColorKeyBubble({
						key: program.get('id')
						colorKeyHex: program.get('colorKeyHex')
						popover: {
							placement: 'right'
							title: program.get('name')
							content: program.get('description')
						}
					})
				)
			)

	return ProgramBubbles

module.exports = {load}
