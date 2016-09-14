# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# View to reorder plan sections & targets

Imm = require 'immutable'
Term = require '../../term'
ImmPropTypes = require 'react-immutable-proptypes'


load = (win) ->
	Bootbox = win.bootbox
	React = win.React
	{PropTypes} = React
	R = React.DOM

	{DragDropContext} = win.ReactDnD
	HTML5Backend = win.ReactDnDHTML5Backend

	PlanSection = require('./planSection').load(win)


	# Wrap top-level component with DragDropContext
	ReorderPlanView = React.createClass
		displayName: 'ReorderPlanView'
		mixins: [React.addons.PureRenderMixin]

		propTypes: {
			plan: ImmPropTypes.map.isRequired
			currentTargetRevisionsById: ImmPropTypes.map.isRequired
			reorderSection: PropTypes.func.isRequired
			reorderTargetId: PropTypes.func.isRequired
		}

		getInitialState: -> {
			displayInactive: false
			displayTargets: true
		}

		render: ->
			{currentTargetRevisionsById, reorderSection, reorderTargetId, plan} = @props
			{displayInactive, displayTargets} = @state

			sections = plan.get('sections')


			return R.div({
				id: 'reorderPlanView'
				className: 'sections' # Match padding of regular plan view
			},
				R.div({className: 'checkbox'},
					R.label({},
						R.input({
							onChange: @_toggleInactive
							checked: displayInactive
							type: 'checkbox'
						})
						"Show inactive"
					)
				)
				R.div({className: 'checkbox'},
					R.label({},
						R.input({
							onChange: @_toggleTargets
							checked: displayTargets
							type: 'checkbox'
						})
						"Show #{Term 'targets'}"
					)
				)
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
					})
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