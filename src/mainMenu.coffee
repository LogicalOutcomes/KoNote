# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Menu component to display MenuOptions

Imm = require 'immutable'
Term = require './term'
Config = require './config'


load = (win) ->
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	OpenDialogLink = require('./openDialogLink').load(win)
	ProgramsDropdown = require('./programsDropdown').load(win)

	if Config.features.shiftSummaries.isEnabled
		GenerateSummariesDialog = require('./generateSummariesDialog').load(win)

	{FaIcon, showWhen} = require('./utils').load(win)


	MainMenu = React.createFactory React.createClass
		displayName: 'MainMenu'
		mixins: [React.addons.PureRenderMixin]

		propTypes: {
			isAdmin: React.PropTypes.bool.isRequired
			programs: React.PropTypes.instanceOf(Imm.List).isRequired
			userProgram: React.PropTypes.instanceOf(Imm.Map)
			managerLayer: React.PropTypes.string
			isSmallHeaderSet: React.PropTypes.bool

			updateManagerLayer: React.PropTypes.func.isRequired
		}

		_overrideProgram: (programId) ->
			program = @props.programs.find (p) =>
				programId is p.get('id')

			currentProgramName = if @props.userProgram
				@props.userProgram.get('name')
			else
				"none"

			newProgramName = if program
				program.get('name')
			else
				"none"

			Bootbox.confirm """
				Override your current #{Term 'program'} (#{currentProgramName})
				to #{newProgramName} for this session?
			"""
			, (ok) =>
				if ok
					# clientSelectionPage listens for new userProgram
					global.ActiveSession.persist.eventBus.trigger 'override:userProgram', program

		render: ->
			{isAdmin} = @props

			userProgramId = if @props.userProgram
				@props.userProgram.get('id')
			else
				''

			return R.aside({
				id: 'mainMenu'
				className: 'animated fadeInRight'
			},
				R.div({id: 'menuContainer'},
					R.div({id: 'user'},
						R.div({},
							R.h3({}, ActiveSession.account.publicInfo.displayName or global.ActiveSession.userName)
							(unless @props.programs.isEmpty()
								ProgramsDropdown({
									selectedProgramId: userProgramId
									programs: @props.programs
									onSelect: @_overrideProgram
								})
							)
						)
					)
					R.div({id: 'items'},
						R.ul({},
							MenuItem({
								title: "#{Term 'Client Files'}"
								icon: 'folder-open'
								onClick: @props.updateManagerLayer.bind null, null
								isActive: @props.managerLayer is null and @props.isSmallHeaderSet
							})
							MenuItem({
								isVisible: Config.features.shiftSummaries.isEnabled
								title: "Shift Summaries"
								icon: 'book'
								onClick: @props.updateManagerLayer.bind null, 'shiftSummariesDialog'
								onClose: @props.updateManagerLayer.bind null, null
								isActive: @props.managerLayer is 'shiftSummariesDialog'
								dialog: GenerateSummariesDialog
							})
							MenuItem({
								title: Term 'Metrics'
								icon: 'line-chart'
								onClick: @props.updateManagerLayer.bind null, 'metricDefinitionManagerTab'
								isActive: @props.managerLayer is 'metricDefinitionManagerTab'
							})
							MenuItem({
								title: Term 'Plan Templates'
								icon: 'wpforms'
								onClick: @props.updateManagerLayer.bind null, 'planTemplateManagerTab'
								isActive: @props.managerLayer is 'planTemplateManagerTab'
							})
							MenuItem({
								isVisible: isAdmin
								title: Term 'Event Types'
								icon: 'calendar-o'
								onClick: @props.updateManagerLayer.bind null, 'eventTypeManagerTab'
								isActive: @props.managerLayer is 'eventTypeManagerTab'
							})
							MenuItem({
								title: Term 'Programs'
								icon: 'users'
								onClick: @props.updateManagerLayer.bind null, 'programManagerTab'
								isActive: @props.managerLayer is 'programManagerTab'
							})
							MenuItem({
								isVisible: isAdmin
								title: "Export Data"
								icon: 'upload'
								onClick: @props.updateManagerLayer.bind null, 'exportManagerTab'
								isActive: @props.managerLayer is 'exportManagerTab'
							})
							MenuItem({
								isVisible: isAdmin
								title: "User #{Term 'Accounts'}"
								icon: 'key'
								onClick: @props.updateManagerLayer.bind null, 'accountManagerTab'
								isActive: @props.managerLayer is 'accountManagerTab'
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
					R.div({title: @props.title},
						FaIcon(@props.icon)
						R.span({className: 'menuItemText'},
							@props.title
						)
					)
			)


	return MainMenu

module.exports = {load}
