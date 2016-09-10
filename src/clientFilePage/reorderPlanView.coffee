# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# View to reorder plan sections & targets

Decorate = require 'es-decorate'


load = (win) ->
	Bootbox = win.bootbox
	React = win.React
	{PropTypes} = React
	R = React.DOM
	{findDOMNode} = win.ReactDOM

	{DragDropContext, DragSource, DropTarget} = win.ReactDnD
	HTML5Backend = win.ReactDnDHTML5Backend

	# Wrap top-level component with DragDropContext
	ReorderPlanView = React.createFactory DragDropContext(HTML5Backend) React.createClass
		displayName: 'ReorderPlanView'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			# Make sections transient (temporary until saved)
			return {
				sections: @props.plan.get('sections')
			}

		render: ->
			{currentTargetRevisionsById} = @props

			sections = @state.sections
			console.log "sections", sections

			return R.div({id: 'reorderPlanView'},
				sections.map (section, index) => PlanSection({
					key: section.get('id')
					id: section.get('id')
					name: section.get('name')
					moveSection: @_moveSection
					index
				})
			)

		_moveSection: (dragIndex, hoverIndex) ->
			dragSection = sections.get(dragIndex)

			sections = sections
			.delete(dragIndex)
			.splice(hoverIndex, 0, dragSection)

			@setState {sections}


	# Drag source contract
	sectionSource = {
		beginDrag: (props) -> {
			id: props.id
			index: props.index
		}
	}

	sectionTarget = {
		hover: (props, monitor, component) ->
			dragIndex = monitor.getItem().index
			hoverIndex = props.index

			# console.log "Props:", props

			# Don't replace items with themselves
			return if dragIndex is hoverIndex

			# Determine rectangle on screen
			hoverBoundingRect = findDOMNode(component).getBoundingClientRect()

			# Get vertical middle
			hoverMiddleY = (hoverBoundingRect.bottom - hoverBoundingRect.top) / 2

			# Determine mouse position
			clientOffset = monitor.getClientOffset()

			# Get pixels to the top
			hoverClientY = clientOffset.y - hoverBoundingRect.top

			# Only perform the move when the mouse has crossed half of the item's height
			# When dragging downwards, only move when the cursor is below 50%
			# When dragging upwards, only move when the cursor is above 50%

			# Dragging downwards
			return if dragIndex < hoverIndex and hoverClientY < hoverMiddleY

			# Dragging upwards
			return if dragIndex > hoverIndex and hoverClientY > hoverMiddleY

			# Time to actually perform the action
			props.moveSection(dragIndex, hoverIndex)

			# (Example says to mutate here, but we're using Imm data)
			monitor.getItem().index = hoverIndex;
	}

	# Specify props to inject into component
	collectSource = (connect, monitor) -> {
		connectDragSource: connect.dragSource()
		isDragging: monitor.isDragging()
	}

	connectTarget = (connect) -> {
		connectDropTarget: connect.dropTarget()
	}


	# Wrap section class with DragSource
	PlanSection = React.createClass
		displayName: 'PlanSection'
		# mixins: [React.addons.PureRenderMixin]

		propTypes: {
			connectDragSource: PropTypes.func.isRequired
			connectDropTarget: PropTypes.func.isRequired
			index: PropTypes.number.isRequired
			isDragging: PropTypes.bool.isRequired
			id: PropTypes.any.isRequired
			name: PropTypes.string.isRequired
			moveSection: PropTypes.func.isRequired
		}

		render: ->
			{name, isDragging, connectDragSource, connectDropTarget} = @props

			console.log "@props", @props

			return connectDragSource connectDropTarget (
				R.section({
					style:
						opacity: 0.5 if isDragging
				},
					name
				)
			)

	# Decorate/Wrap PlanSection with DropTarget and DragSource
	PlanSection = React.createFactory Decorate [
		DropTarget('section', sectionTarget, connectTarget)
		DragSource('section', sectionSource, collectSource)
	], PlanSection


	return ReorderPlanView


module.exports = {load}