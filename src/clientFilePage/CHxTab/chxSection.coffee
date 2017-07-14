# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Chx section view, which is draggable

Imm = require 'immutable'
Decorate = require 'es-decorate'
Term = require '../../term'


load = (win) ->
	React = win.React
	R = React.DOM
	{findDOMNode} = win.ReactDOM
	{DragSource, DropTarget} = win.ReactDnD

	ChxTopic = require('./chxTopic').load(win)
	InactiveToggleWrapper = require('./inactiveToggleWrapper').load(win)
	StatusButtonGroup = require('./statusButtonGroup').load(win)
	ModifySectionStatusDialog = require('../modifyChxSectionStatusDialog').load(win)
	ColorKeyBubble = require('../../colorKeyBubble').load(win)

	{FaIcon, showWhen} = require('../../utils').load(win)


	ChxSection = React.createClass
		displayName: 'ChxSection'
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
			# Methods
			reorderSection: React.PropTypes.func.isRequired
			reorderTopicId: React.PropTypes.func.isRequired
		}

		getInitialState: -> {
			displayDeactivatedTopics: null
			displayCompletedTopics: null
			isReorderHovered: false
		}

		render: ->
			{
				section
				program
				clientFile
				chx
				currentTopicRevisionsById
				chxTopicsById
				selectedTopicId

				isReadOnly
				isCollapsed

				renameSection
				addTopicToSection
				hasTopicChanged
				updateTopic
				removeNewTopic
				removeNewSection
				onRemoveNewSection
				setSelectedTopic
				addMetricToTopic
				deleteMetricFromTopic
				getSectionIndex
				expandTopic
				expandSection

				reorderSection
				reorderTopicId

				connectDragSource
				connectDropTarget
				connectDragPreview
				isDragging
			} = @props

			{id, status} = section.toObject()

			sectionIsInactive = status isnt 'default'
			sectionIndex = @props.index

			# Build topics by status, and order them manually into an array
			# TODO: Make this an ordered set or something...
			topicsByStatus = section.get('topicIds')
			.map (id) -> currentTopicRevisionsById.get(id)
			.groupBy (t) -> t.get('status')

			topicsByStatusArray = Imm.List(['default', 'completed', 'deactivated']).map (status) ->
				topicsByStatus.get(status)


			return connectDropTarget connectDragPreview (
				R.section({
					id: "section-#{id}"
					className: [
						'chxSection'
						"status-#{status}"
						'isCollapsed' if isCollapsed
						'isDragging' if isDragging
						'isReorderHovered' if @state.isReorderHovered
					].join ' '
				},
					SectionHeader({
						clientFile
						section
						program
						isReadOnly
						isCollapsed
						allTopicsAreInactive: not topicsByStatus.get('default')

						renameSection
						getSectionIndex
						addTopicToSection
						onRemoveNewSection
						sectionIsInactive
						currentTopicRevisionsById
						connectDragSource
						expandSection
						onReorderHover: @_onReorderHover
					})

					(if section.get('topicIds').size is 0
						R.div({className: 'noTopics'},
							"This #{Term 'section'} is empty."
						)
					)

					(topicsByStatusArray.map (topics) =>
						# TODO: Remove this in favour of [key, value] (prev. TODO)
						return if not topics
						status = topics.getIn [0, 'status']
						size = topics.size

						# Build the list of topics
						ChxTopicsList = R.div({className: 'chxTopicsList'},
							(topics.map (topic) =>
								topicId = topic.get('id')
								index = section.get('topicIds').indexOf topicId

								hasChanges = hasTopicChanged(topicId)
								isSelected = topicId is selectedTopicId
								isExistingTopic = chxTopicsById.has(topicId)

								ChxTopic({
									key: topicId
									topic
									hasChanges
									isSelected
									isExistingTopic
									isReadOnly
									isCollapsed
									sectionIsInactive

									onRemoveNewTopic: removeNewTopic.bind null, id, topicId
									onTopicUpdate: updateTopic.bind null, topicId
									onTopicSelection: setSelectedTopic.bind null, topicId
									setSelectedTopic # allows for setState cb
									onExpandTopic: expandTopic.bind null, topicId

									addMetricToTopic
									deleteMetricFromTopic

									reorderTopicId
									section
									sectionIndex
									index
								})
							)
						)

						# Return wrapped inactive topic groups for display toggling
						R.div({key: status},
							switch status
								when 'default'
									ChxTopicsList

								when 'deactivated'
									InactiveToggleWrapper({
										children: ChxTopicsList
										dataType: 'topic'
										status, size
										isExpanded: @state.displayDeactivatedTopics
										onToggle: @_toggleDisplayDeactivatedTopics
									})

								when 'completed'
									InactiveToggleWrapper({
										children: ChxTopicsList
										dataType: 'topic'
										status, size
										isExpanded: @state.displayCompletedTopics
										onToggle: @_toggleDisplayCompletedTopics
									})
						)

					)

				)
			)

		_toggleDisplayCompletedTopics: ->
			displayCompletedTopics = not @state.displayCompletedTopics
			@setState {displayCompletedTopics}

		_toggleDisplayDeactivatedTopics: ->
			displayDeactivatedTopics = not @state.displayDeactivatedTopics
			@setState {displayDeactivatedTopics}

		_onReorderHover: (isReorderHovered) -> @setState {isReorderHovered}


	SectionHeader = React.createFactory React.createClass
		displayName: 'SectionHeader'
		mixins: [React.addons.PureRenderMixin]

		render: ->
			{
				clientFile
				section
				program
				isReadOnly
				isCollapsed
				allTopicsAreInactive

				renameSection
				getSectionIndex
				addTopicToSection
				removeNewSection
				onRemoveNewSection
				currentTopicRevisionsById
				sectionIsInactive
				connectDragSource
				expandSection
				onReorderHover
			} = @props

			sectionStatus = section.get('status')
			sectionId = section.get('id')

			# Figure out whether already exists in chx
			isExistingSection = clientFile.getIn(['chx','sections']).some (obj) =>
				obj.get('id') is section.get('id')

			canSetStatus = isExistingSection and (allTopicsAreInactive or sectionIsInactive) and not isReadOnly
			canModify = not isReadOnly and not sectionIsInactive
			isAdmin = global.ActiveSession.isAdmin()


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
						onClick: ->
							if isCollapsed
								expandSection(sectionId)
							else if canModify
								renameSection(sectionId)
					},
						section.get('name')

						(if program
							ColorKeyBubble({
								colorKeyHex: program.get('colorKeyHex')
								popover: {
									title: program.get('name')
									content: program.get('description')
									placement: 'top'
								}
							})
						)

						(if canModify and not isCollapsed
							FaIcon('pencil', {className: 'renameIcon'})
						)
					)
				)

				(if canSetStatus and isAdmin
					StatusButtonGroup({
						chxElementType: Term 'Section'
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
				(if not sectionIsInactive and isAdmin
					R.div({className: 'btn-group btn-group-sm sectionButtons'},
						R.button({
							ref: 'addTopic'
							className: 'addTopic btn btn-primary'
							onClick: addTopicToSection.bind null, section.get('id')
							disabled: not canModify
						},
							FaIcon('plus')
							" Add #{Term 'Topic'}"
						)
					)
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


	# Decorate/Wrap ChxSection with DragDropContext, DropTarget, and DragSource
	return React.createFactory Decorate [
		DropTarget('section', sectionDestination, connectDestination)
		DragSource('section', sectionSource, collectSource)
	], ChxSection


module.exports = {load}
