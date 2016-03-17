# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

load = (win) ->
	# Libraries from browser context
	$ = win.jQuery
	React = win.React
	R = React.DOM

	ProgramBubbles = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		render: ->
			programs = @props.programs.sortBy (program) -> program.get('name').toLowerCase()

			R.div({className: 'programBubbles'}, 
				programs.map (program) -> 
					ProgramBubble({
						program
						key: program.get('id')
					})
			)

	ProgramBubble = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		componentDidMount: ->
			$(@refs.bubble).popover {
				trigger: 'hover'
				placement: 'right'
				title: @props.program.get('name') if @props.program?
				content: @props.program.get('description') if @props.program?
			}

		render: ->
			R.div({
				className: 'programBubble'
				ref: 'bubble'
				style:
					background: @props.colorKeyHex or @props.program.get('colorKeyHex')
			})


	return {ProgramBubble, ProgramBubbles}

module.exports = {load}
