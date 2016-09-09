# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# View to reorder plan sections & targets

load = (win) ->
	Bootbox = win.bootbox
	React = win.React
	{PropTypes} = React
	R = React.DOM

	{DragSource, DragDropContext} = win.ReactDnD
	HTML5Backend = win.ReactDnDHTML5Backend

	# Wrap top-level component with DragDropContext
	ReorderPlanView = React.createFactory DragDropContext(HTML5Backend) React.createClass
		displayName: 'ReorderPlanView'
		mixins: [React.addons.PureRenderMixin]

		render: ->
			{plan, currentTargetRevisionsById} = @props

			sections = plan.get('sections')
			console.log "sections", sections.toJS()

			return R.div({id: 'reorderPlanView'},
				sections.map (section) -> PlanSection({name: section.get('name')})
			)


	# Drag source contract
	sectionSource = {
		beginDrag: (props) -> {
			name: props.name
		}
	}

	# Specify props to inject into component
	collect = (connect, monitor) -> {
		connectDragSource: connect.dragSource()
		isDragging: monitor.isDragging()
	}

	# Wrap section class with DragSource
	PlanSection = React.createFactory DragSource('section', sectionSource, collect) React.createClass
		displayName: 'PlanSection'
		mixins: [React.addons.PureRenderMixin]

		propTypes: {
			name: PropTypes.string.isRequired

			# Injected by ReactDnD
			isDragging: PropTypes.bool.isRequired
			connectDragSource: PropTypes.func.isRequired
		}

		render: ->
			{name, isDragging, connectDragSource} = @props

			return connectDragSource R.section({
				style:
					opacity: 0.5 if isDragging
			},
				name
			)


	return ReorderPlanView


module.exports = {load}