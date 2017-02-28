# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Main view component for Plan Tab in client file
# Wrapped in main drag-drop context, to re-order sections & targets

Term = require '../../term'


load = (win) ->
	Bootbox = win.bootbox
	React = win.React
	{PropTypes} = React
	R = React.DOM
	{findDOMNode} = win.ReactDOM

	{DragDropContext} = win.ReactDnD
	HTML5Backend = win.ReactDnDHTML5Backend

	PlanSection = require('./planSection').load(win)
	{DropdownButton, MenuItem} = require('../../utils/reactBootstrap').load(win, 'DropdownButton', 'MenuItem')

	{FaIcon, showWhen, scrollToElement} = require('../../utils').load(win)


	PlanView = React.createClass
		displayName: 'PlanView'
		mixins: [React.addons.PureRenderMixin]

		propTypes: {
			isCollapsed: PropTypes.bool.isRequired
		}

		getInitialState: -> {
			displayDeactivatedSections: false
			displayCompletedSections: false
		}



		render: ->
			{
				clientFile, plan, metricsById
				currentTargetRevisionsById, planTargetsById, selectedTargetId
				isReadOnly, isCollapsed

				renameSection, reorderSection, getSectionIndex
				reorderTargetId
				addTargetToSection
				hasTargetChanged
				updateTarget
				removeNewTarget
				removeNewSection
				setSelectedTarget
				addMetricToTarget
				deleteMetricFromTarget
			} = @props

			{sections} = plan.toObject()

			if sections.isEmpty()
				return null

			sectionsByStatus = sections.groupBy (s) -> s.get('status')

			activeSections = sectionsByStatus.get('default')
			completedSections = sectionsByStatus.get('completed')
			deactivatedSections = sectionsByStatus.get('deactivated')


			return R.div({id: 'planView'},

				(activeSections.map (section) =>
					id = section.get('id')
					index = sections.indexOf section

					PlanSection({
						ref: "section-#{id}"
						key: id
						id

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
						setSelectedTarget
						addMetricToTarget
						deleteMetricFromTarget
						getSectionIndex
						onRemoveNewSection: -> removeNewSection(section)
						expandTarget: @_expandTarget

						reorderSection
						reorderTargetId
						index
					})
				)

				# (if completedSections
				# 	R.div({className: 'sections status-completed'},
				# 		R.span({
				# 			className: 'inactiveSectionHeader'
				# 			onClick: => @_toggleDisplayCompletedSections()
				# 		},
				# 			# Rotates 90'CW when expanded
				# 			FaIcon('caret-right', {
				# 				className: 'expanded' if @state.displayCompletedSections
				# 			})
				# 			R.strong({}, completedSections.size)
				# 			" Completed "
				# 			Term (
				# 				if completedSections.size > 1 then 'Sections' else 'Section'
				# 			)
				# 		)

				# 		(if @state.displayCompletedSections
				# 			# Completed status
				# 			(completedSections.map (section) =>
				# 				PlanSection({
				# 					key: section.get('id')
				# 					ref: 'section-' + section.get('id')

				# 					section
				# 					clientFile
				# 					plan
				# 					metricsById
				# 					currentTargetRevisionsById
				# 					planTargetsById
				# 					selectedTargetId
				# 					isReadOnly

				# 					renameSection
				# 					addTargetToSection
				# 					hasTargetChanged
				# 					updateTarget
				# 					removeNewTarget
				# 					removeNewSection
				# 					onRemoveNewSection: removeNewSection.bind null, section
				# 					setSelectedTarget
				# 					addMetricToTarget
				# 					deleteMetricFromTarget
				# 					getSectionIndex
				# 				})
				# 			)
				# 		)
				# 	)
				# )

				# (if deactivatedSections
				# 	R.div({className: 'sections status-deactivated'},
				# 		R.span({
				# 			className: 'inactiveSectionHeader'
				# 			onClick: => @_toggleDisplayDeactivatedSections()
				# 		},
				# 			# Rotates 90'CW when expanded
				# 			FaIcon('caret-right', {
				# 				className: 'expanded' if @state.displayDeactivatedSections
				# 			})
				# 			R.strong({}, deactivatedSections.size)
				# 			" Deactivated "
				# 			Term (
				# 				if deactivatedSections.size > 1 then 'Sections' else 'Section'
				# 			)
				# 		)

				# 		(if @state.displayDeactivatedSections
				# 			# Deactivated status
				# 			(deactivatedSections.map (section) =>
				# 				PlanSection({
				# 					key: section.get('id')
				# 					ref: 'section-' + section.get('id')

				# 					section
				# 					clientFile
				# 					plan
				# 					metricsById
				# 					currentTargetRevisionsById
				# 					planTargetsById
				# 					selectedTargetId
				# 					isReadOnly

				# 					renameSection
				# 					addTargetToSection
				# 					hasTargetChanged
				# 					updateTarget
				# 					removeNewTarget
				# 					removeNewSection
				# 					onRemoveNewSection: removeNewSection.bind null, section
				# 					setSelectedTarget
				# 					addMetricToTarget
				# 					deleteMetricFromTarget
				# 					getSectionIndex
				# 				})
				# 			)
				# 		)
				# 	)
				# )
			)

		_toggleDisplayDeactivatedSections: (boolean, cb=(->)) ->
			displayDeactivatedSections = boolean or not @state.displayDeactivatedSections
			@setState {displayDeactivatedSections}, cb

		_toggleDisplayCompletedSections: (boolean, cb=(->)) ->
			displayCompletedSections = boolean or not @state.displayCompletedSections
			@setState {displayCompletedSections}, cb

		_expandSection: (section) ->
			{id, status} = section.toObject()
			sectionElementId = "section-#{id}"

			# Highlight the destination in seperate op (regardless of valid scroll or not)
			$sectionName = $("##{sectionElementId} .sectionName")
			$sectionName.addClass 'highlight'
			setTimeout (=> $sectionName.removeClass 'highlight'), 1750

			@setState {isCollapsed: false}, =>
				stickyHeaderOffset = $('.sectionHeader').innerHeight() * -1
				@_scrollTo sectionElementId, stickyHeaderOffset, cb
				# Done scrolling to section, highlighting removed on its own

		_expandTarget: (target, section) ->
			{id, status} = target.toObject()
			targetElementId = "target-#{id}"

			additionalOffset = if @props.isReadOnly
				$('#readOnlyNotice').innerHeight() * -1
			else
				0

			# Switch views & select target, expand groups if needed, scroll!
			@props.collapseAndSelectTargetId id, => @_scrollTo(targetElementId, additionalOffset)

		_scrollTo: (elementId, additionalOffset, cb=(->)) ->
			$container = findDOMNode(@)
			$element = win.document.getElementById(elementId)

			topOffset = 50 + additionalOffset # Add offset depending on top padding
			scrollToElement $container, $element, 1000, 'easeInOutQuad', topOffset, cb


	# Create drag-drop context for the PlanView class
	return React.createFactory DragDropContext(HTML5Backend) PlanView


module.exports = {load}