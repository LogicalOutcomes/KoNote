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

	{DragSource, DropTarget} = win.ReactDnD

	PlanTarget = require('./planTarget').load(win)


	# We wrap this with a factory when decorating
	PlanSection = React.createClass
		displayName: 'PlanSection'

		propTypes: {
			connectDragSource: PropTypes.func.isRequired
			connectDropTarget: PropTypes.func.isRequired
			index: PropTypes.number.isRequired
			isDragging: PropTypes.bool.isRequired
			id: PropTypes.any.isRequired
			name: PropTypes.string.isRequired
			reorderSection: PropTypes.func.isRequired
			targets: ImmPropTypes.list.isRequired
		}

		render: ->
			{name, isDragging, connectDragSource, connectDropTarget, targets, reorderTargetId} = @props

			console.log "Targets:", targets.toJS()

			return connectDragSource connectDropTarget (
				R.section({
					style:
						opacity: 0.5 if isDragging
				},
					R.h4({}, name)
					R.div({className: 'targets'},
						(targets.map (target, index) =>
							PlanTarget({
								key: target.get('id')
								id: target.get('id')
								target
								index
								sectionIndex: @props.index
								reorderTargetId
							})
						)
					)
				)
			)


	# Drag source contract
	sectionSource = {
		beginDrag: (props) -> {
			id: props.id
			index: props.index
		}
	}

	sectionDestination = {
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

			# Time to actually perform the action
			props.reorderSection(dragIndex, hoverIndex)

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


	# Decorate/Wrap PlanSection with DragDropContext, DropTarget, and DragSource
	return React.createFactory Decorate [
		DropTarget('section', sectionDestination, connectDestination)
		DragSource('section', sectionSource, collectSource)
	], PlanSection


module.exports = {load}