# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Plan section view, which is draggable

Imm = require 'immutable'
Decorate = require 'es-decorate'
Term = require '../../term'


load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM
	{findDOMNode} = win.ReactDOM
	{DragSource, DropTarget} = win.ReactDnD

	PlanTarget = require('./planTarget').load(win)
	StatusButtonGroup = require('./statusButtonGroup').load(win)
	ModifySectionStatusDialog = require('../modifySectionStatusDialog').load(win)
	OpenDialogLink = require('../../openDialogLink').load(win)
	WithTooltip = require('../../withTooltip').load(win)
	CreatePlanTemplateDialog = require('../createPlanTemplateDialog').load(win)

	{FaIcon, showWhen, scrollToElement} = require('../../utils').load(win)


	PlanSection = React.createClass
		displayName: 'PlanSection'
		mixins: [React.addons.PureRenderMixin]

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
		}

		getInitialState: -> {
			displayCancelledTargets: null
			displayCompletedTargets: null
			isReorderHovered: false
		}

		render: ->
			{
				section
				clientFile
				plan
				metricsById
				currentTargetRevisionsById
				planTargetsById
				selectedTargetId

				isReadOnly
				isCollapsed

				renameSection
				addTargetToSection
				hasTargetChanged
				updateTarget
				removeNewTarget
				removeNewSection
				onRemoveNewSection
				setSelectedTarget
				addMetricToTarget
				deleteMetricFromTarget
				getSectionIndex
				expandTarget

				reorderSection
				reorderTargetId

				connectDragSource
				connectDropTarget
				connectDragPreview
				isDragging
			} = @props

			{id, status} = section.toObject()

			sectionIsInactive = status isnt 'default'
			sectionIndex = @props.index

			targetsByStatus = section.get('targetIds')
			.map (id) -> currentTargetRevisionsById.get(id)
			.groupBy (target) -> target.get('status')

			activeTargets = targetsByStatus.get('default')
			completedTargets = targetsByStatus.get('completed')
			deactivatedTargets = targetsByStatus.get('deactivated')


			return connectDropTarget connectDragPreview (
				R.section({
					id: "section-#{id}"
					className: [
						'planSection'
						"status-#{status}"
						'isCollapsed' if isCollapsed
						'isDragging' if isDragging
						'isReorderHovered' if @state.isReorderHovered
					].join ' '
				},
					SectionHeader({
						clientFile
						section
						isReadOnly
						allTargetsAreInactive: not activeTargets

						renameSection
						getSectionIndex
						addTargetToSection
						onRemoveNewSection
						sectionIsInactive
						currentTargetRevisionsById
						connectDragSource
						onReorderHover: (isReorderHovered) => @setState {isReorderHovered}
					})

					(if section.get('targetIds').size is 0
						R.div({className: 'noTargets'},
							"This #{Term 'section'} is empty."
						)
					)

					# TODO: Generalize these 3 into a single component

					(if activeTargets
						# Default status
						TargetsList({
							targets: activeTargets
							selectedTargetId
							section, sectionIndex
							currentTargetRevisionsById, metricsById, planTargetsById
							removeNewTarget, updateTarget, setSelectedTarget, hasTargetChanged
							expandTarget, addMetricToTarget, deleteMetricFromTarget, reorderTargetId
							isReadOnly, isCollapsed
						})
					)

					# Inactive targets are pushed to the bottom

					(if completedTargets
						R.div({className: 'targets status-completed'},
							R.span({
								className: 'inactiveTargetHeader'
								onClick: => @_toggleDisplayCompletedTargets()
							},
								# Rotates 90'CW when expanded
								FaIcon('caret-right', {
									className: 'expanded' if @state.displayCompletedTargets
								})
								R.strong({}, completedTargets.size)
								" Completed "
								Term (
									if completedTargets.size > 1 then 'Targets' else 'Target'
								)
							)
							(if @state.displayCompletedTargets
								# Completed status
								TargetsList({
									targets: completedTargets
									selectedTargetId
									section, sectionIndex
									currentTargetRevisionsById, metricsById, planTargetsById
									removeNewTarget, updateTarget, setSelectedTarget, hasTargetChanged
									expandTarget, addMetricToTarget, deleteMetricFromTarget, reorderTargetId
									isReadOnly, isCollapsed
								})
							)
						)
					)
					(if deactivatedTargets
						R.div({className: 'targets status-deactivated'},
							R.span({
								className: 'inactiveTargetHeader'
								onClick: => @_toggleDisplayCancelledTargets()
							},
								# Rotates 90'CW when expanded
								FaIcon('caret-right', {
									className: 'expanded' if @state.displayDeactivatedTargets
								})
								R.strong({}, deactivatedTargets.size)
								" Deactivated "
								Term (
									if deactivatedTargets.size > 1 then 'Targets' else 'Target'
								)
							)
							(if @state.displayDeactivatedTargets
								# Completed status
								TargetsList({
									targets: deactivatedTargets
									selectedTargetId
									section, sectionIndex
									currentTargetRevisionsById, metricsById, planTargetsById
									removeNewTarget, updateTarget, setSelectedTarget, hasTargetChanged
									expandTarget, addMetricToTarget, deleteMetricFromTarget, reorderTargetId
									isReadOnly, isCollapsed
								})
							)

						)
					)
				)
			)

		_toggleDisplayDeactivatedTargets: (boolean, cb=(->)) ->
			displayDeactivatedTargets = boolean or not @state.displayDeactivatedTargets
			@setState {displayDeactivatedTargets}, cb

		_toggleDisplayCompletedTargets: (boolean, cb=(->)) ->
			displayCompletedTargets = boolean or not @state.displayCompletedTargets
			@setState {displayCompletedTargets}, cb


	SectionHeader = React.createFactory React.createClass
		displayName: 'SectionHeader'
		mixins: [React.addons.PureRenderMixin]

		render: ->
			{
				clientFile
				section
				isReadOnly
				allTargetsAreInactive

				renameSection
				getSectionIndex
				addTargetToSection
				removeNewSection
				onRemoveNewSection
				currentTargetRevisionsById
				sectionIsInactive
				connectDragSource
				onReorderHover
			} = @props

			sectionStatus = section.get('status')

			# Figure out whether already exists in plan
			isExistingSection = clientFile.getIn(['plan','sections']).some (obj) =>
				obj.get('id') is section.get('id')

			canSetStatus = isExistingSection and allTargetsAreInactive
			canModify = not isReadOnly and not sectionIsInactive


			return R.div({className: 'sectionHeader'},
				connectDragSource (
					R.div({
						className: 'dragSource'
						onMouseOver: => onReorderHover(true)
						onMouseLeave: => onReorderHover(false)
					},
						FaIcon('arrows-v')
					)
				)

				R.div({
					title: "Edit name"
					className: 'sectionName'
				},
					R.span({
						onClick: -> if canModify then renameSection(section.get('id'))
					},
						section.get('name')

						(if canModify
							FaIcon('pencil', {className: 'renameIcon'})
						)
					)
				)

				# TODO: Extract to component
				(if canSetStatus
					StatusButtonGroup({
						planElementType: Term 'Section'
						data: section
						parentData: clientFile
						isExisting: isExistingSection
						status: sectionStatus
						onRemove: onRemoveNewSection
						dialog: ModifySectionStatusDialog
						isDisabled: isReadOnly
					})
				)

				# TODO: Extract to component
				(unless sectionIsInactive
					R.div({className: 'btn-group btn-group-sm sectionButtons'},
						R.button({
							ref: 'addTarget'
							className: 'addTarget btn btn-primary'
							onClick: addTargetToSection.bind null, section.get('id')
							disabled: not canModify
						},
							FaIcon('plus')
							" Add #{Term 'Target'}"
						)

						WithTooltip({
							title: "Create #{Term 'Section'} #{Term 'Template'}"
							placement: 'top'
							container: 'body'
						},
							OpenDialogLink({
								className: 'btn btn-default'
								dialog: CreatePlanTemplateDialog
								title: "Create #{Term 'Template'} from #{Term 'Section'}"
								sections: Imm.List([section])
								currentTargetRevisionsById
								disabled: isReadOnly
							},
								FaIcon 'wpforms'
							)
						)
					)
				)
			)


	TargetsList = (props) ->
		{
			targets, section, sectionIndex, sectionIsInactive, selectedTargetId
			currentTargetRevisionsById, metricsById, planTargetsById
			removeNewTarget, updateTarget, setSelectedTarget, hasTargetChanged
			expandTarget, addMetricToTarget, deleteMetricFromTarget, reorderTargetId
			isReadOnly, isCollapsed
		} = props

		{id, status} = section.toObject()


		return R.div({className: "targetsList status-#{status}"},
			(targets.map (target) =>
				targetId = target.get('id')
				index = section.get('targetIds').indexOf targetId

				hasChanges = hasTargetChanged(targetId)
				isInactive = sectionIsInactive or target.get('status') isnt 'default'
				isSelected = targetId is selectedTargetId
				isExistingTarget = planTargetsById.has(targetId)

				PlanTarget({
					key: targetId
					target
					metricsById
					hasChanges
					isSelected
					isInactive
					isExistingTarget
					isReadOnly
					isCollapsed

					onRemoveNewTarget: removeNewTarget.bind null, id, targetId
					onTargetUpdate: updateTarget.bind null, targetId
					onTargetSelection: setSelectedTarget.bind null, targetId
					setSelectedTarget # allows for setState cb
					onExpandTarget: expandTarget.bind null, target, section

					addMetricToTarget
					deleteMetricFromTarget
					targetId

					reorderTargetId
					section
					sectionIndex
					index
				})
			)
		)


	# Drag source contract
	sectionSource = {
		beginDrag: ({id, index}) -> {id, index}
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
