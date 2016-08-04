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
	{FaIcon} = require('./utils').load(win)

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
			# userProgram can be null, so bypasses getDefaultProps
			userProgram = @props.userProgram or Imm.Map()

			remainingPrograms = @props.programs.filterNot (program) =>
				userProgram.get('id') is program.get('id')

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
						style: { borderBottomColor: userProgram.get('colorKeyHex')}
					},
						userProgram.get('name') or "No #{Term 'Program'}"
					)
				},
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
					(if not remainingPrograms.isEmpty() and @props.userProgram
						B.MenuItem({divider: true})
					)
					(if @props.userProgram
						B.MenuItem({
							onClick: @props.onSelect.bind null, null
						},
							"None "
							FaIcon('ban')
						)
					)
				)
			)


	return UserProgramDropdown

module.exports = {load}
