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
	{DragSource, DropTarget} = win.ReactDnD

	PlanTarget = require('./planTarget').load(win)
	{FaIcon} = require('../../utils').load(win)


	PlanSection = React.createClass
		displayName: 'PlanSection'

		getInitialState: -> {
			isHovered: null
		}

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
			section: React.PropTypes.instanceOf(Imm.Map).isRequired
			targets: React.PropTypes.instanceOf(Imm.List).isRequired
			# Methods
			reorderSection: React.PropTypes.func.isRequired
			reorderTargetId: React.PropTypes.func.isRequired
			# Options
			displayInactive: React.PropTypes.bool.isRequired
			displayTargets: React.PropTypes.bool.isRequired
		}

		render: ->
			{
				name, section, targets,
				connectDragSource, connectDropTarget, connectDragPreview, isDragging
				displayInactive, displayTargets, reorderTargetId, scrollToTarget
			} = @props

			sectionIndex = @props.index
			sectionId = section.get('id')

			sectionIsInactive = section.get('status') isnt 'default'
			sectionIsHidden = not displayInactive and sectionIsInactive

			visibleTargets = if not displayInactive
				targets.filter (t) -> t.get('status') is 'default'
			else
				targets


			return connectDropTarget connectDragPreview(
				R.section({
					className: [
						'planSection'
						'hasTargets' if not visibleTargets.isEmpty() and displayTargets
						'isDragging' if isDragging
						'isHovered' if @state.isHovered
						'collapsed' if sectionIsHidden
					].join ' '
				},
					R.div({className: 'sectionNameContainer'},
						connectDragSource(
							R.div({
								className: 'dragSource sectionDragSource'
								onMouseOver: => @setState {isHovered: true}
								onMouseOut: => @setState {isHovered: false}
							},
								FaIcon('arrows-v')
							)
						)
						R.div({
							className: 'name'
							onClick: => @props.scrollToSection(section)
						},
							name
						)
					)
					(if displayTargets and not targets.isEmpty()
						R.div({className: 'targets'},
							(targets.map (target, index) =>
								PlanTarget({
									key: target.get('id')
									id: target.get('id')
									target, section
									index
									sectionIndex
									reorderTargetId
									displayInactive
									scrollToTarget
								})
							)
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
		connectDragPreview: connect.dragPreview()
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