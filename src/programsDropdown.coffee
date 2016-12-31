# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Dropdown component for program selection, minus selected program

Imm = require 'immutable'
Term = require './term'


load = (win) ->
	Bootbox = win.bootbox
	React = win.React
	{PropTypes} = React
	R = React.DOM

	B = require('./utils/reactBootstrap').load(win, 'DropdownButton', 'MenuItem')

	ColorKeyBubble = require('./colorKeyBubble').load(win)
	{FaIcon} = require('./utils').load(win)


	ProgramsDropdown = React.createFactory React.createClass
		displayName: 'ProgramsDropdown'
		mixins: [React.addons.PureRenderMixin]

		propTypes: {
			selectedProgram: React.PropTypes.instanceOf(Imm.Map)
			programs: React.PropTypes.instanceOf(Imm.List).isRequired
			placeholder: React.PropTypes.string
			onSelect: React.PropTypes.func.isRequired
		}

		getDefaultProps: -> {
			selectedProgram: Imm.Map()
			placeholder: "No #{Term 'Program'}"
			excludeNone: false
		}

		getInitialState: -> {
			isOpen: null
		}

		toggle: ->
			@setState {isOpen: not @state.isOpen}

		render: ->
			# selectedProgram can be null, so bypasses getDefaultProps
			selectedProgram = @props.selectedProgram or Imm.Map()

			remainingPrograms = @props.programs.filterNot (program) =>
				selectedProgram.get('id') is program.get('id')

			R.span({
				className: 'programsDropdown'
				onClick: @toggle
			},
				B.DropdownButton({
					ref: 'dropdown'
					id: 'programsDropdown'
					open: @state.isOpen
					onClose: @toggle
					bsStyle: 'link'
					pullRight: true
					container: 'body'

					title: R.span({
						className: 'currentProgram'
						style: { borderBottomColor: selectedProgram.get('colorKeyHex')}
					},
						selectedProgram.get('name') or @props.placeholder
					)
				},
					(remainingPrograms
					.filter (program) =>
						program.get('status') is 'default'

					.map (program) =>
						B.MenuItem({
							key: program.get('id')
							onClick: @props.onSelect.bind null, program
						},
							program.get('name')
							' '
							ColorKeyBubble({colorKeyHex: program.get('colorKeyHex')})
						)
					)
					(if not remainingPrograms.isEmpty() and @props.selectedProgram and not @props.excludeNone
						B.MenuItem({divider: true})
					)
					(if @props.selectedProgram and not @props.excludeNone
						B.MenuItem({
							onClick: @props.onSelect.bind null, null
						},
							"None "
							FaIcon('ban')
						)
					)
				)
			)


	return ProgramsDropdown

module.exports = {load}
