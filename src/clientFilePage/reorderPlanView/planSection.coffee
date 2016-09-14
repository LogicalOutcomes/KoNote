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
			# DnD
			connectDragSource: PropTypes.func.isRequired
			connectDropTarget: PropTypes.func.isRequired
			isDragging: PropTypes.bool.isRequired
			# DnD props
			index: PropTypes.number.isRequired
			id: PropTypes.any.isRequired
			# Raw data
			section: ImmPropTypes.map.isRequired
			targets: ImmPropTypes.list.isRequired
			# Methods
			reorderSection: PropTypes.func.isRequired
			reorderTargetId: PropTypes.func.isRequired
			# Options
			displayInactive: PropTypes.bool.isRequired
			displayTargets: PropTypes.bool.isRequired
		}

		render: ->
			{name, isDragging, connectDragSource, section, targets,
			displayInactive, displayTargets
			connectDropTarget, targets, reorderTargetId} = @props

			sectionIndex = @props.index

			sectionIsInactive = section.get('status') isnt 'default'
			sectionIsHidden = not displayInactive and sectionIsInactive


			return connectDragSource connectDropTarget (
				R.section({
					className: [
						'planSection'
						'isDragging' if isDragging
						'collapsed' if sectionIsHidden
					].join ' '
				},
					R.h4({}, name)
					R.div({className: 'targets'},
						(targets.map (target, index) =>
							PlanTarget({
								key: target.get('id')
								id: target.get('id')
								target
								index
								sectionIndex
								reorderTargetId
								displayInactive
								isCollapsed: not displayTargets
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