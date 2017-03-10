# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Main view component for Plan Tab in client file
# Wrapped in main drag-drop context, to re-order sections & targets
# Handles auto-scrolling behaviour

Imm = require 'immutable'
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
	InactiveToggleWrapper = require('./inactiveToggleWrapper').load(win)
	{DropdownButton, MenuItem} = require('../../utils/reactBootstrap').load(win, 'DropdownButton', 'MenuItem')

	{FaIcon, showWhen, scrollToElement} = require('../../utils').load(win)


	PlanView = React.createClass
		displayName: 'PlanView'
		mixins: [React.addons.PureRenderMixin]
		# TODO: propTypes

		getInitialState: -> {
			displayDeactivatedSections: false
			displayCompletedSections: false
		}

		render: ->
			planSections = @props.plan.get('sections')

			if planSections.isEmpty()
				return null

			# Build sections by status, and order them manually into an array
			# TODO: Make this an ordered set or something...
			sectionsByStatus = planSections.groupBy (s) -> s.get('status')
			sectionsByStatusArray = Imm.List(['default', 'completed', 'deactivated']).map (status) ->
				sectionsByStatus.get(status)

			return R.div({id: 'planView'},

				(sectionsByStatusArray.map (sections) =>
					# TODO: Remove this in favour of [key, value] (prev. TODO)
					return null if not sections
					status = sections.getIn [0, 'status']
					size = sections.size

					# Build the list of sections
					PlanSectionsList = R.div({
						key: status
						className: 'sections'
					},
						(sections.map (section) =>
							id = section.get('id')
							index = planSections.indexOf section
							sectionIsInactive = section.get('status') isnt 'default'

							props = Object.assign {}, @props, {
								ref: "section-#{id}"
								key: id
								section, id, index
								expandTarget: @_expandTarget
								expandSection: @_expandSection
							}

							return PlanSection(props)
						)
					)

					# Return wrapped inactive section groups for display toggling
					# Needs to be wrapped in a keyed div, for the key to work
					return R.div({
						id: "sections-#{status}"
						key: status
					},
						switch status
							when 'default'
								PlanSectionsList

							when 'deactivated'
								InactiveToggleWrapper({
									children: PlanSectionsList
									dataType: 'section'
									status, size
									isExpanded: @state.displayDeactivatedSections
									onToggle: @_toggleDisplayDeactivatedSections
								})

							when 'completed'
								InactiveToggleWrapper({
									children: PlanSectionsList
									dataType: 'section'
									status, size
									isExpanded: @state.displayCompletedSections
									onToggle: @_toggleDisplayCompletedSections
								})
					)
				)
			)

		_toggleDisplayCompletedSections: ->
			displayCompletedSections = not @state.displayCompletedSections
			@setState {displayCompletedSections}, =>
				# Scroll top of inactive sections container when expanded
				if displayCompletedSections
					@scrollTo "sections-completed"

		_toggleDisplayDeactivatedSections: ->
			displayDeactivatedSections = not @state.displayDeactivatedSections

			@setState {displayDeactivatedSections}, =>
				# Scroll top of inactive sections container when expanded
				if displayDeactivatedSections
					 @scrollTo "sections-deactivated"

		_expandTarget: (id) ->
			elementId = "target-#{id}"

			# Account for read-only notice on top if isReadOnly
			additionalOffset = if @props.isReadOnly
				$('#readOnlyNotice').innerHeight() * -1
			else
				0

			additionalOffset += 25 # Add a bit extra for sectionHeader

			# Switch views & select target, expand groups if needed, scroll!
			@props.collapseAndSelectTargetId id, => @scrollTo(elementId, additionalOffset)

		_expandSection: (id) ->
			elementId = "section-#{id}"

			additionalOffset = 0

			# TODO: Make sections selectable (ie: section history)
			@props.toggleCollapsedView => @scrollTo(elementId, additionalOffset)

		scrollTo: (elementId, additionalOffset=0, cb=(->)) ->
			# We have CSS animations in play, wait 250ms before measuring scroll destination
			setTimeout (=>
				$container = findDOMNode(@)
				$element = win.document.getElementById(elementId)

				scrollToElement $container, $element, 1000, 'easeInOutQuad', additionalOffset, cb
			), 250


	# Create drag-drop context for the PlanView class
	return React.createFactory DragDropContext(HTML5Backend) PlanView


module.exports = {load}