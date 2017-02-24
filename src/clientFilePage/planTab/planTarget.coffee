# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

Imm = require 'immutable'
Decorate = require 'es-decorate'
Term = require '../../term'


load = (win) ->
	$ = win.jQuery
	React = win.React
	R = React.DOM
	{findDOMNode} = win.ReactDOM
	{DragSource, DropTarget} = win.ReactDnD

	ExpandingTextArea = require('../../expandingTextArea').load(win)
	WithTooltip = require('../../withTooltip').load(win)
	ModifyTargetStatusDialog = require('../modifyTargetStatusDialog').load(win)
	MetricLookupField = require('../../metricLookupField').load(win)
	MetricWidget = require('../../metricWidget').load(win)
	OpenDialogLink = require('../../openDialogLink').load(win)
	PrintButton = require('../../printButton').load(win)

	{FaIcon} = require('../../utils').load(win)


	PlanTarget = React.createClass
		displayName: 'PlanTarget'
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
			target: React.PropTypes.instanceOf(Imm.Map).isRequired
			# Methods
			reorderTargetId: React.PropTypes.func.isRequired
		}

		render: ->
			{
				target
				connectDropTarget, connectDragPreview, connectDragSource
			} = @props

			{id, status, name, description, metricIds} = target.toObject()

			targetIsInactive = @props.isReadOnly or @props.isInactive or @props.sectionIsInactive


			return connectDropTarget connectDragPreview connectDragSource (
				R.div({
					id: "target-#{id}"
					className: [
						"target target-#{id}"
						"status-#{status}"
						'isSelected' if @props.isSelected
						'isInactive' if targetIsInactive
						'hasChanges' if @props.hasTargetChanged or not @props.isExistingTarget
						'readOnly' if @props.isReadOnly
					].join ' '
					onMouseDown: @_onTargetClick
				},

					R.div({className: 'nameContainer'},
						R.input({
							type: 'text'
							className: 'name field form-control'
							ref: 'nameField'
							placeholder: "Name of #{Term 'target'}"
							value: name
							onChange: @_updateField.bind null, 'name'
							onFocus: @props.onTargetSelection
							onClick: @props.onTargetSelection
							disabled: targetIsInactive
						})

						(if not @props.hasTargetChanged and @props.isExistingTarget and not @props.sectionIsInactive
							(if @props.isExistingTarget
								# Can cancel/complete a 'default' target
								(if status is 'default'
									R.div({className: 'statusButtonGroup'},
										WithTooltip({title: "Deactivate #{Term 'Target'}", placement: 'top'},
											OpenDialogLink({
												className: 'statusButton'
												dialog: ModifyTargetStatusDialog
												planTarget: target
												newStatus: 'deactivated'
												title: "Deactivate #{Term 'Target'}"
												message: """
													This will remove the #{Term 'target'} from the #{Term 'client'}
													#{Term 'plan'}, and future #{Term 'progress notes'}.
													It may be re-activated again later.
												"""
												reasonLabel: "Reason for deactivation:"
												disabled: targetIsInactive
											},
												FaIcon 'times'
											)
										)
										WithTooltip({title: "Complete #{Term 'Target'}", placement: 'top'},
											OpenDialogLink({
												className: 'statusButton'
												dialog: ModifyTargetStatusDialog
												planTarget: target
												newStatus: 'completed'
												title: "Complete #{Term 'Target'}"
												message: """
													This will set the #{Term 'target'} as 'completed'. This often
													means that the desired outcome has been reached.
												"""
												reasonLabel: "Reason for completion:"
												disabled: targetIsInactive
											},
												FaIcon 'check'
											)
										)
									)
								else
									R.div({className: 'statusButtonGroup'},
										WithTooltip({title: "Re-Activate #{Term 'Target'}", placement: 'top'},
											OpenDialogLink({
												className: 'statusButton'
												dialog: ModifyTargetStatusDialog
												planTarget: target
												newStatus: 'default'
												title: "Re-Activate #{Term 'Target'}"
												message: """
													This will re-activate the #{Term 'target'}, so it appears
													in the #{Term 'client'} #{Term 'plan'} and
													future #{Term 'progress notes'}.
												"""
												reasonLabel: "Reason for activation:"
												disabled: @props.isReadOnly
											},
												FaIcon 'sign-in'
											)
										)
									)
								)
							else
								R.div({className: 'statusButtonGroup'},
									R.div({
										className: 'statusButton'
										onClick: @props.onRemoveNewTarget
										title: 'Cancel'
									},
										FaIcon 'times'
									)
								)
							)
						)
					)

					R.div({className: 'descriptionContainer'},
						ExpandingTextArea({
							className: 'description field'
							ref: 'descriptionField'
							placeholder: "Describe the current #{Term 'treatment plan'} . . ."
							value: description
							disabled: targetIsInactive
							onChange: @_updateField.bind null, 'description'
							onFocus: @props.onTargetSelection
							onClick: @props.onTargetSelection
						})
					)
					(if not metricIds.isEmpty() or @props.isSelected
						R.div({className: 'metrics'},
							R.div({className: 'metricsList'},
								(metricIds.map (metricId) =>
									metric = @props.metricsById.get(metricId)

									MetricWidget({
										name: metric.get('name')
										definition: metric.get('definition')
										value: metric.get('value')
										key: metricId
										tooltipViewport: '.view'
										isEditable: false
										allowDeleting: not targetIsInactive
										onDelete: @props.deleteMetricFromTarget.bind(
											null, @props.targetId, metricId
										)
									})
								)
								(if @props.isSelected and not targetIsInactive
									R.button({
										className: "btn btn-link addMetricButton animated fadeIn"
										onClick: @_focusMetricLookupField.bind(null, @props.targetId)
									},
										FaIcon('plus')
										" Add #{Term 'metric'}"
									)
								)
							)
							(unless targetIsInactive
								R.div({
									className: 'metricLookupContainer'
									ref: 'metricLookup'
								},
									MetricLookupField({
										metrics: @props.metricsById.valueSeq().filter (metric) => metric.get('status') is 'default'
										onSelection: @props.addMetricToTarget.bind(
											null, @props.targetId, @_hideMetricInput
										)
										placeholder: "Find / Define a #{Term 'Metric'}"
										isReadOnly: @props.isReadOnly
										onBlur: @_hideMetricInput
									})
								)
							)
						)
					)
				)
			)

		_updateField: (fieldName, event) ->
			newValue = @props.target.set fieldName, event.target.value
			@props.onTargetUpdate(newValue)

		_onTargetClick: (event) ->
			@props.onTargetSelection()

			unless (
				(event.target.classList.contains 'field') or
				(event.target.classList.contains 'lookupField') or
				(event.target.classList.contains 'btn')
			)
				@refs.nameField.focus() unless @props.isReadOnly

		_focusMetricLookupField: ->
			$(@refs.metricLookup).show()
			$('.lookupField').focus()

		_hideMetricInput: ->
			$(@refs.metricLookup).hide()


	# Drag source contract
	targetSource = {
		beginDrag: ({id, index, sectionIndex}) -> {id, index, sectionIndex}
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


	# Wrap (decorate) planTarget with drag-drop
	return React.createFactory Decorate [
		DropTarget('target', targetDestination, connectDestination)
		DragSource('target', targetSource, collectSource)
	], PlanTarget


module.exports = {load}
