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
	ModifyTopicStatusDialog = require('../modifyTopicStatusDialog').load(win)
	ExpandingTextArea = require('../../expandingTextArea').load(win)

	{FaIcon, scrollToElement} = require('../../utils').load(win)


	ChxTopic = React.createClass
		displayName: 'ChxTopic'
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
			topic: React.PropTypes.instanceOf(Imm.Map).isRequired
			# Methods
			reorderTopicId: React.PropTypes.func.isRequired
		}

		render: ->
			{
				topic, sectionIsInactive
				isSelected, isReadOnly, isCollapsed, isExistingTopic, hasChanges
				connectDropTarget, connectDragPreview, connectDragSource
				onExpandTopic
			} = @props

			{id, status, name, description} = topic.toObject()

			canChangeStatus = (
				isSelected and
				not sectionIsInactive and
				not isReadOnly and
				isExistingTopic
			)

			isDisabled = (
				isReadOnly or
				status isnt 'default' or
				sectionIsInactive or isReadOnly
			)


			return connectDropTarget connectDragPreview (
				R.div({
					id: "topic-#{id}"
					className: [
						'chxTopic'
						"status-#{status}"
						'isSelected' if isSelected
						'hasChanges' if hasChanges or not isExistingTopic
						'isCollapsed' if isCollapsed
						'readOnly' if isReadOnly
						'dragging' if @props.isDragging
					].join ' '
					onClick: @props.onTopicSelection
				},
					connectDragSource (
						R.div({
							className: 'dragSource'
						},
							FaIcon('arrows-v')
						)
					)

					R.div({className: 'chxTopicContainer'},
						R.div({className: 'nameContainer'},
							(if isCollapsed
								R.span({
									className: 'name field static'
									onClick: @props.onExpandTopic
								},
									name
								)
							else
								R.input({
									ref: 'nameField'
									className: 'form-control name field'
									type: 'text'
									value: name
									placeholder: "Name of #{Term 'topic'}"
									onChange: @_updateField.bind null, 'name'
									onFocus: @props.onTopicSelection
									onClick: @props.onTopicSelection
									disabled: isDisabled
								})
							)

							(if canChangeStatus
								StatusButtonGroup({
									chxElementType: Term 'Topic'
									data: topic
									isExisting: isExistingTopic
									status
									onRemove: null
									dialog: ModifyTopicStatusDialog
								})
							)
						)

						R.div({className: 'descriptionContainer'},
							ExpandingTextArea({
								className: 'description field'
								placeholder: "#{Term 'chx'} . . ."
								value: description
								disabled: isDisabled
								onChange: @_updateField.bind null, 'description'
								onFocus: @props.onTopicSelection
								onClick: @props.onTopicSelection
							})
						)
					)
				)
			)

		_updateField: (fieldName, event) ->
			newValue = @props.topic.set fieldName, event.target.value
			@props.onTopicUpdate(newValue)

		###
  		# todo: do we need this?
		_onTopicClick: (event) ->
			classList = event.target.classList
			# Prevent distracting switching of selectedTopic while re-ordering topics
			return if classList.contains 'dragSource'

			# Clicking anywhere but the fields or buttons will focus the name field
			shouldFocusNameField = not (
				(classList.contains 'field') or
				(classList.contains 'lookupField') or
				(classList.contains 'btn') or
				@props.isReadOnly
			)

			@props.setSelectedTopic @props.topic.get('id'), =>
				@_focusNameField() if shouldFocusNameField
		###

		_focusNameField: ->
			@refs.nameField.focus() if @refs.nameField?


	# Drag source contract
	targetSource = {
		beginDrag: ({id, index, sectionIndex}) -> {id, index, sectionIndex}
	}

	topicDestination = {
		hover: (props, monitor, component) ->
			draggingTopicProps = monitor.getItem()

			sectionIndex = draggingTopicProps.sectionIndex
			dragIndex = draggingTopicProps.index
			hoverIndex = props.index

			# Don't replace items with themselves
			return if dragIndex is hoverIndex

			# Can't drag topic to another section
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
			props.reorderTopicId(sectionIndex, dragIndex, hoverIndex)

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


	# Wrap (decorate) chxTopic with drag-drop
	return React.createFactory Decorate [
		DropTarget('topic', topicDestination, connectDestination)
		DragSource('topic', targetSource, collectSource)
	], ChxTopic


module.exports = {load}
