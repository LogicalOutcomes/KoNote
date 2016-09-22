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


	PlanTarget = React.createClass
		display: 'PlanTarget'

		propTypes: {
			# DnD
			connectDragSource: PropTypes.func.isRequired
			connectDropTarget: PropTypes.func.isRequired
			isDragging: PropTypes.bool.isRequired
			# DnD props
			index: PropTypes.number.isRequired
			id: PropTypes.any.isRequired
			# Raw data
			target: ImmPropTypes.map.isRequired
			# Methods
			reorderTargetId: PropTypes.func.isRequired
			# Options
			displayInactive: PropTypes.bool.isRequired
		}

		render: ->
			{target, connectDragSource, connectDropTarget,
			isCollapsed, isDragging, displayInactive} = @props

			targetIsInactive = target.get('status') isnt 'default'
			targetIsHidden = isCollapsed or (not displayInactive and targetIsInactive)

			return connectDragSource connectDropTarget (
				R.div({
					className: [
						'planTarget'
						'isDragging' if isDragging
						'collapsed' if targetIsHidden
					].join ' '
				},
					target.get('name')
				)
			)


	# Drag source contract
	targetSource = {
		beginDrag: (props) -> {
			id: props.id
			index: props.index
			sectionIndex: props.sectionIndex
		}
	}

	targetDestination = {
		hover: (props, monitor, component) ->
			draggingTargetProps = monitor.getItem()

			sectionIndex = draggingTargetProps.sectionIndex
			dragIndex = draggingTargetProps.index
			hoverIndex = props.index

			# Don't replace items with themselves
			return if dragIndex is hoverIndex

			# Can't drag target to another section
			return if sectionIndex isnt props.sectionIndex

			# Determine rectangle on screen
			hoverBoundingRect = findDOMNode(component).getBoundingClientRect()

			# Get vertical middle
			hoverMiddleTopY = (hoverBoundingRect.bottom - hoverBoundingRect.top) / 4
			hoverMiddleBottomY = hoverMiddleTopY * 3

			# Determine mouse position
			clientOffset = monitor.getClientOffset()

			# Get pixels to the top
			hoverClientY = clientOffset.y - hoverBoundingRect.top

			# Only perform the move when the mouse has crossed half of the item's height
			# When dragging downwards, only move when the cursor is below 50%
			# When dragging upwards, only move when the cursor is above 50%

			# Dragging downwards
			return if dragIndex < hoverIndex and hoverClientY < hoverMiddleTopY

			# Dragging upwards
			return if dragIndex > hoverIndex and hoverClientY > hoverMiddleBottomY

			# Time to actually perform the action
			props.reorderTargetId(sectionIndex, dragIndex, hoverIndex)

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


	# Decorate/Wrap PlanTarget
	return React.createFactory Decorate [
		DropTarget('target', targetDestination, connectDestination)
		DragSource('target', targetSource, collectSource)
	], PlanTarget


module.exports = {load}