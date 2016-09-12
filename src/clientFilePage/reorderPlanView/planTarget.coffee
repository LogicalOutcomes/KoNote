# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# View to reorder plan sections & targets

Decorate = require 'es-decorate'
ImmPropTypes = require 'react-immutable-proptypes'

load = (win) ->
	Bootbox = win.bootbox
	React = win.React
	{PropTypes} = React
	R = React.DOM
	{findDOMNode} = win.ReactDOM

	{DragDropContext, DragSource, DropTarget} = win.ReactDnD
	HTML5Backend = win.ReactDnDHTML5Backend


	# Drag source contract
	targetSource = {
		beginDrag: (props) -> {
			id: props.id
			index: props.index
		}
	}

	targetDestination = {
		hover: (props, monitor, component) ->
			dragIndex = monitor.getItem().index
			hoverIndex = props.index

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

			## SPECIAL CONDITION: Can't drag to another section


			# Time to actually perform the action
			props.reorderTargetId(dragIndex, hoverIndex)

			# (Example says to mutate here, but we're using Imm data)
			monitor.getItem().index = hoverIndex;
	}



	# Specify props to inject into component
	collectSource = (connect, monitor) -> {
		connectDragSource: connect.dragSource()
		isDragging: monitor.isDragging()
	}

	connectDestination = (connect) -> {
		connectDropTarget: connect.dropTarget()
	}


	PlanTarget = React.createClass
		display: 'PlanTarget'

		propTypes: {
			target: ImmPropTypes.map.isRequired
		}

		render: ->
			{target, connectDragSource, connectDropTarget} = @props

			return connectDragSource connectDropTarget (
				R.div({},
					target.get('name')
				)
			)

	# Decorate/Wrap PlanSection with DragDropContext, DropTarget, and DragSource
	PlanTarget = React.createFactory Decorate [
		DropTarget('target', targetDestination, connectDestination)
		DragSource('target', targetSource, collectSource)
	], PlanTarget



	return PlanTarget


module.exports = {load}