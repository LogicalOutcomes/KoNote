# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# View to reorder plan sections & targets

Imm = require 'immutable'
Decorate = require 'es-decorate'

load = (win) ->
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM
	{findDOMNode} = win.ReactDOM
	{DragDropContext, DragSource, DropTarget} = win.ReactDnD
	HTML5Backend = win.ReactDnDHTML5Backend

	{FaIcon} = require('../../utils').load(win)


	PlanTarget = React.createClass
		display: 'PlanTarget'

		propTypes: {
			# DnD
			connectDragSource: React.PropTypes.func.isRequired
			connectDragPreview: React.PropTypes.func.isRequired
			connectDropTarget: React.PropTypes.func.isRequired
			isDragging: React.PropTypes.bool.isRequired
			# DnD props
			index: React.PropTypes.number.isRequired
			id: React.PropTypes.any.isRequired
			# Raw data
			target: React.PropTypes.instanceOf(Imm.Map).isRequired
			# Methods
			reorderTargetId: React.PropTypes.func.isRequired
			# Options
			displayInactive: React.PropTypes.bool.isRequired
		}

		render: ->
			{
				connectDragSource, connectDragPreview, connectDropTarget, isDragging
				target, displayInactive
			} = @props

			isCollapsed = not displayInactive and target.get('status') isnt 'default'


			return connectDropTarget connectDragPreview(
				R.div({
					className: [
						'planTarget'
						'isDragging' if isDragging
						'collapsed' if isCollapsed
					].join ' '
				},
					connectDragSource(
						R.div({className: 'dragSource targetDragSource'},
							FaIcon('arrows-v')
						)
					)

					R.div({className: 'targetContainer'},
						R.span({className: 'name'},
							target.get('name')
						)
					)
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
		connectDragPreview: connect.dragPreview()
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