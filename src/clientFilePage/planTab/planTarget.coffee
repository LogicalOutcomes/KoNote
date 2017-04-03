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

	StatusButtonGroup = require('./statusButtonGroup').load(win)
	ModifyTargetStatusDialog = require('../modifyTargetStatusDialog').load(win)
	MetricLookupField = require('../../metricLookupField').load(win)
	ExpandingTextArea = require('../../expandingTextArea').load(win)
	MetricWidget = require('../../metricWidget').load(win)

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
			# Raw data
			target: React.PropTypes.instanceOf(Imm.Map).isRequired
			# Methods
			reorderTargetId: React.PropTypes.func.isRequired
		}

		render: ->
			{
				target, sectionIsInactive
				isSelected, isReadOnly, isCollapsed, isExistingTarget, hasChanges
				connectDropTarget, connectDragPreview, connectDragSource
				onExpandTarget
			} = @props

			{id, status, name, description, metricIds} = target.toObject()

			canChangeStatus = (
				isSelected and
				not sectionIsInactive and
				not isReadOnly and
				isExistingTarget
			)

			isDisabled = (
				isReadOnly or
				status isnt 'default' or
				sectionIsInactive or isReadOnly
			)


			return connectDropTarget connectDragPreview (
				R.div({
					id: "target-#{id}"
					className: [
						'planTarget'
						"status-#{status}"
						'isSelected' if isSelected
						'hasChanges' if hasChanges or not isExistingTarget
						'isCollapsed' if isCollapsed
						'readOnly' if isReadOnly
						'dragging' if @props.isDragging
					].join ' '
					onClick: @props.onTargetSelection
				},
					connectDragSource (
						R.div({
							className: 'dragSource'
						},
							FaIcon('arrows-v')
						)
					)

					R.div({className: 'planTargetContainer'},
						R.div({className: 'nameContainer'},
							(if isCollapsed
								R.span({
									className: 'name field static'
									onClick: @props.onExpandTarget
								},
									name
								)
							else
								R.input({
									ref: 'nameField'
									className: 'form-control name field'
									type: 'text'
									value: name
									placeholder: "Name of #{Term 'target'}"
									onChange: @_updateField.bind null, 'name'
									onFocus: @props.onTargetSelection
									onClick: @props.onTargetSelection
									disabled: isDisabled
								})
							)

							(if canChangeStatus
								StatusButtonGroup({
									planElementType: Term 'Target'
									data: target
									isExisting: isExistingTarget
									status
									onRemove: null
									dialog: ModifyTargetStatusDialog
								})
							)
						)

						R.div({className: 'descriptionContainer'},
							ExpandingTextArea({
								className: 'description field'
								placeholder: "Describe the current #{Term 'treatment plan'} . . ."
								value: description
								disabled: isDisabled
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
											allowDeleting: not isDisabled
											onDelete: @props.deleteMetricFromTarget.bind(
												null, id, metricId
											)
										})
									)
									(if @props.isSelected and not isDisabled
										R.button({
											className: "btn btn-link addMetricButton animated fadeIn"
											onClick: @_focusMetricLookupField.bind(null, id)
										},
											FaIcon('plus')
											" Add #{Term 'metric'}"
										)
									)
								)
								(unless isDisabled
									R.div({
										ref: 'metricLookup'
										className: 'metricLookupContainer'
									},
										MetricLookupField({
											metrics: @props.metricsById.valueSeq().filter (metric) => metric.get('status') is 'default'
											onSelection: @props.addMetricToTarget.bind(
												null, id, @_hideMetricInput
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
			)

		_updateField: (fieldName, event) ->
			newValue = @props.target.set fieldName, event.target.value
			@props.onTargetUpdate(newValue)

		###
  		# todo: do we need this?
		_onTargetClick: (event) ->
			classList = event.target.classList
			# Prevent distracting switching of selectedTarget while re-ordering targets
			return if classList.contains 'dragSource'

			@props.onTargetSelection

			# Clicking anywhere but the fields or buttons will focus the name field
			shouldFocusNameField = not (
				(classList.contains 'field') or
				(classList.contains 'lookupField') or
				(classList.contains 'btn') or
				@props.isReadOnly
			)

			@props.setSelectedTarget @props.target.get('id'), =>
				@_focusNameField() if shouldFocusNameField
		###

		_focusNameField: ->
			@refs.nameField.focus() if @refs.nameField?

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
