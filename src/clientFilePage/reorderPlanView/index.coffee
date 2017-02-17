# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# View to reorder plan sections & targets

Imm = require 'immutable'
Term = require '../../term'


load = (win) ->
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	{DragDropContext} = win.ReactDnD
	HTML5Backend = win.ReactDnDHTML5Backend

	PlanSection = require('./planSection').load(win)


	# Wrap top-level component with DragDropContext
	ReorderPlanView = React.createClass
		displayName: 'ReorderPlanView'
		mixins: [React.addons.PureRenderMixin]

		propTypes: {
			plan: React.PropTypes.instanceOf(Imm.Map).isRequired
			currentTargetRevisionsById: React.PropTypes.instanceOf(Imm.Map).isRequired
			reorderSection: React.PropTypes.func.isRequired
			reorderTargetId: React.PropTypes.func.isRequired
		}

		getInitialState: -> {
			displayInactive: false
			displayTargets: true
		}

		render: ->
			{
				plan
				currentTargetRevisionsById, reorderSection, reorderTargetId,
				scrollToSection, scrollToTarget
			} = @props

			{displayInactive, displayTargets} = @state

			sections = plan.get('sections')

			# Sum of sections' targets
			numberOfTargets = sections.reduce ((last, s) -> last + s.get('targetIds').size), 0

			numberOfItems = sections.size + numberOfTargets
			shrinkFontSize = numberOfItems > 16

			return R.div({id: 'reorderPlanView'},
				R.div({className: 'flexFiltersToolbar'},
					R.aside({}, "Show:")
					R.section({},
						R.label({},
							R.input({
								onChange: @_toggleTargets
								checked: displayTargets
								type: 'checkbox'
							})
							"#{Term 'Targets'}"
						)
					)
					R.section({},
						R.label({},
							R.input({
								onChange: @_toggleInactive
								checked: displayInactive
								type: 'checkbox'
							})
							"Inactive Items"
						)
					)
				)

				R.div({
					id: 'reorderContainer'
					className: [
						'sections'
						'shrinkFontSize' if shrinkFontSize
					].join ' '
				},
					(sections.map (section, index) =>
						targets = section.get('targetIds').map (id) -> currentTargetRevisionsById.get(id)

						PlanSection({
							key: section.get('id')
							index
							id: section.get('id')
							name: section.get('name')
							section
							targets
							reorderSection
							reorderTargetId
							displayInactive
							displayTargets
							scrollToSection
							scrollToTarget
						})
					)
				)
			)

		_toggleInactive: ->
			displayInactive = not @state.displayInactive
			@setState {displayInactive}

		_toggleTargets: ->
			displayTargets = not @state.displayTargets
			@setState {displayTargets}


	return React.createFactory DragDropContext(HTML5Backend) ReorderPlanView


module.exports = {load}