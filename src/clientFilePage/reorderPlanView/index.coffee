# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# View to reorder plan sections & targets

load = (win) ->
	Bootbox = win.bootbox
	React = win.React
	{PropTypes} = React
	R = React.DOM

	{DragDropContext} = win.ReactDnD
	HTML5Backend = win.ReactDnDHTML5Backend

	PlanSection = require('./planSection').load(win)


	# Wrap top-level component with DragDropContext
	ReorderPlanView = React.createFactory DragDropContext(HTML5Backend) React.createClass
		displayName: 'ReorderPlanView'
		mixins: [React.addons.PureRenderMixin]

		render: ->
			{currentTargetRevisionsById, reorderSection, reorderTargetId} = @props

			sections = @props.plan.get('sections')

			return R.div({
				id: 'reorderPlanView'
				className: 'sections' # Match padding of regular plan view
			},
				(sections.map (section, index) =>
					targets = section.get('targetIds').map (id) -> currentTargetRevisionsById.get(id)

					PlanSection({
						key: section.get('id')
						index
						id: section.get('id')
						name: section.get('name')
						targets
						reorderSection
						reorderTargetId
					})
				)
			)


	return ReorderPlanView


module.exports = {load}