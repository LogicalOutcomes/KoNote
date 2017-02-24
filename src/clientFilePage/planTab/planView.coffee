# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Main view component for Plan Tab in client file
# Wrapped in main drag-drop context, to re-order sections & targets

Term = require '../../term'


load = (win) ->
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	{DragDropContext} = win.ReactDnD
	HTML5Backend = win.ReactDnDHTML5Backend

	PlanSection = require('./planSection').load(win)
	{DropdownButton, MenuItem} = require('../../utils/reactBootstrap').load(win, 'DropdownButton', 'MenuItem')

	{FaIcon, showWhen, scrollToElement} = require('../../utils').load(win)


	PlanView = React.createClass
		displayName: 'PlanView'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: -> {
			displayDeactivatedSections: false
			displayCompletedSections: false
		}
		# TODO: propTypes

		# expandSection: (section, cb) ->
		# 	{status, id} = section.toObject()

		# 	switch status
		# 		when 'default'
		# 			cb()
		# 		when 'completed'
		# 			@_toggleDisplayCompletedSections(true, cb)
		# 		when 'deactivated'
		# 			@_toggleDisplayDeactivatedSections(true, cb)
		# 		else
		# 			throw new Error "Unknown status: #{status}"

		# expandTarget: (target, section, cb) ->
		# 	sectionId = section.get('id')
		# 	status = target.get('status')
		# 	# First ensure the section is available
		# 	@expandSection section, =>
		# 		# Ask it to expand completed/deactivated targets
		# 		@refs["section-#{sectionId}"].expandTargetsWithStatus status, cb

		render: ->
			{
				clientFile
				plan
				metricsById
				currentTargetRevisionsById
				planTargetsById
				selectedTargetId
				isReadOnly
				isVisible

				renameSection
				addTargetToSection
				hasTargetChanged
				updateTarget
				removeNewTarget
				removeNewSection
				setSelectedTarget
				addMetricToTarget
				deleteMetricFromTarget
				getSectionIndex

				reorderSection
				reorderTargetId
			} = @props


			if plan.get('sections').isEmpty()
				return null

			sectionsByStatus = plan.get('sections').groupBy (s) -> s.get('status')

			activeSections = sectionsByStatus.get('default')
			completedSections = sectionsByStatus.get('completed')
			deactivatedSections = sectionsByStatus.get('deactivated')


			return R.div({id: 'planView'},

				(activeSections.map (section) =>
					id = section.get('id')
					index = plan.get('sections').indexOf section

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


	# Create drag-drop context for the PlanView class
	return React.createFactory DragDropContext(HTML5Backend) PlanView


module.exports = {load}