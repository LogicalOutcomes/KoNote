# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Node libs
ImmPropTypes = require 'react-immutable-proptypes'
Term = require './term'

load = (win) ->
	# Window libs
	Bootbox = win.bootbox
	React = win.React
	{PropTypes} = React
	R = React.DOM

	B = require('./utils/reactBootstrap').load(win, 'DropdownButton', 'MenuItem')

	WithTooltip = require('./withTooltip').load(win)
	ColorKeyBubble = require('./colorKeyBubble').load(win)
	OpenDialogLink = require('./openDialogLink').load(win)
	CreateClientFileDialog = require('./createClientFileDialog').load(win)
	UserProgramDropdown = require('./userProgramDropdown').load(win)

	{FaIcon, showWhen} = require('./utils').load(win)


	MainMenu = React.createFactory React.createClass
		displayName: 'MainMenu'
		mixins: [React.addons.PureRenderMixin]

		propTypes: {
			isAdmin: PropTypes.bool.isRequired
			programs: ImmPropTypes.list.isRequired
			userProgram: ImmPropTypes.map.isRequired
			managerLayer: PropTypes.string

			updateManagerLayer: PropTypes.func.isRequired
		}

		_overrideProgram: (program) ->
			Bootbox.confirm """
				Override your current #{Term 'program'} (#{@props.userProgram.get('name')})
				to #{program.get('name')} for this session?
			"""
			, (ok) =>
				if ok
					# clientSelectionPage listens for new userProgram
					global.ActiveSession.persist.eventBus.trigger 'override:userProgram', program

		render: ->
			{isAdmin} = @props

			R.aside({
				id: 'mainMenu'
				className: 'isOpen animated fadeInRight'
			},
				R.div({id: 'menuContainer'},
					R.div({id: 'user'},
						R.div({},
							R.div({id: 'avatar'}, FaIcon('user'))
							R.h3({}, global.ActiveSession.userName)
							(if @props.userProgram?
								UserProgramDropdown({
									userProgram: @props.userProgram
									programs: @props.programs
									onSelect: @_overrideProgram
								})
							)
						)
					)
					R.div({id: 'items'},
						R.ul({},
							MenuItem({
								title: "New #{Term 'Client File'}"
								icon: 'folder-open'
								dialog: CreateClientFileDialog
								programs: @props.programs
								onClick: @props.updateManagerLayer.bind null, null
							})
							MenuItem({
								isVisible: isAdmin
								title: "User #{Term 'Accounts'}"
								icon: 'key'
								onClick: @props.updateManagerLayer.bind null, 'accountManagerTab'
								isActive: @props.managerLayer is 'accountManagerTab'
							})
							MenuItem({
								title: Term 'Programs'
								icon: 'users'
								onClick: @props.updateManagerLayer.bind null, 'programManagerTab'
								isActive: @props.managerLayer is 'programManagerTab'
							})
							MenuItem({
								isVisible: isAdmin
								title: "#{Term 'Event'} Types"
								icon: 'calendar-o'
								onClick: @props.updateManagerLayer.bind null, 'eventTypeManagerTab'
								isActive: @props.managerLayer is 'eventTypeManagerTab'
							})
							MenuItem({
								title: Term 'Metrics'
								icon: 'line-chart'
								onClick: @props.updateManagerLayer.bind null, 'metricDefinitionManagerTab'
								isActive: @props.managerLayer is 'metricDefinitionManagerTab'
							})
							MenuItem({
								title: "Plan Templates"
								icon: 'wpforms'
								onClick: @props.updateManagerLayer.bind null, 'planTemplateManagerTab'
								isActive: @props.managerLayer is 'planTemplateManagerTab'
							})
							MenuItem({
								isVisible: isAdmin
								title: "Export Data"
								icon: 'upload'
								onClick: @props.updateManagerLayer.bind null, 'exportManagerTab'
								isActive: @props.managerLayer is 'exportManagerTab'
							})
							MenuItem({
								title: "My #{Term 'Account'}"
								icon: 'cog'
								onClick: @props.updateManagerLayer.bind null, 'myAccountManagerTab'
								isActive: @props.managerLayer is 'myAccountManagerTab'
							})
						)
					)
				)
			)


	MenuItem = React.createFactory React.createClass
		displayName: 'MenuItem'
		mixins: [React.addons.PureRenderMixin]

		getDefaultProps: ->
			return {
				isVisible: true
				isActive: false
				onClick: ->
				dialog: null
			}

		render: ->
			return R.li({
				className: [
					'active' if @props.isActive
					showWhen @props.isVisible
				].join ' '
				onClick: @props.onClick
			},
				if @props.dialog?
					OpenDialogLink(@props,
						FaIcon(@props.icon)
						@props.title
					)
				else
					R.div({},
						FaIcon(@props.icon)
						@props.title
					)
			)


	return MainMenu

module.exports = {load}
