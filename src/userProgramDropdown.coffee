# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Node libs
Imm = require 'immutable'
ImmPropTypes = require 'react-immutable-proptypes'
Term = require './term'

load = (win) ->
	# Window libs
	Bootbox = win.bootbox
	React = win.React
	{PropTypes} = React
	R = React.DOM
	B = require('./utils/reactBootstrap').load(win, 'DropdownButton', 'MenuItem')

	ColorKeyBubble = require('./colorKeyBubble').load(win)

	UserProgramDropdown = React.createFactory React.createClass
		displayName: 'UserProgramSelection'
		mixins: [React.addons.PureRenderMixin]

		propTypes: {
			userProgram: ImmPropTypes.map
			programs: ImmPropTypes.list.isRequired
			onSelect: PropTypes.func.isRequired
		}

		getDefaultProps: ->
			return {
				userProgram: Imm.Map()
			}

		getInitialState: ->
			return {
				isOpen: null
			}

		toggle: ->
			@setState {isOpen: not @state.isOpen}

		render: ->
			remainingPrograms = @props.programs.filterNot (program) =>
				@props.userProgram.get('id') is program.get('id')

			R.span({
				className: 'userProgramDropdown'
				onClick: @toggle
			},
				B.DropdownButton({
					ref: 'userProgramDropdown'
					id: 'userProgramDropdown'
					open: @state.isOpen
					onClose: @toggle
					bsStyle: 'link'
					pullRight: true
					container: 'body'

					title: R.span({
						className: 'currentProgram'
						style: { borderBottomColor: @props.userProgram.get('colorKeyHex')}
					},
						@props.userProgram.get('name') or "No #{Term 'Program'}"
					)
				},
					(if remainingPrograms.isEmpty()
						B.MenuItem({header: true},
							"No other #{Term 'programs'}"
						)
					)
					(remainingPrograms.map (program) =>
						B.MenuItem({
							key: program.get('id')
							onClick: @props.onSelect.bind null, program
						},
							program.get('name')
							' '
							ColorKeyBubble({colorKeyHex: program.get('colorKeyHex')})
						)
					)
				)
			)


	return UserProgramDropdown

module.exports = {load}
