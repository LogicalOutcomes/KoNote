# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Main view component for Plan Tab in client file
# Wrapped in main drag-drop context, to re-order sections & targets

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
			sectionsByStatusArray = Imm.List(['default', 'deactivated', 'completed']).map (status) ->
				sectionsByStatus.get(status)

			return R.div({id: 'planView'},

				(sectionsByStatusArray.map (sections) =>
					# TODO: Remove this in favour of [key, value] (prev. TODO)
					return null if not sections
					status = sections.getIn [0, 'status']
					size = sections.size

					# Build the list of sections
					PlanSectionsList = R.div({className: 'sections'},
						(sections.map (section) =>
							id = section.get('id')
							index = planSections.indexOf section
							sectionIsInactive = section.get('status') isnt 'default'

							props = Object.assign {}, @props, {
								ref: "section-#{id}"
								key: id
								section, id, index
								expandTarget: @_expandTarget
							}

							return PlanSection(props)
						)
					)

					# Wrap inactive section groups for display toggling
					switch status
						when 'default'
							PlanSectionsList

						when 'completed'
							InactiveSectionsWrapper({
								status, size
								isExpanded: @state.displayCompletedSections
								onToggle: @_toggleDisplayCompletedSections
							},
								PlanSectionsList
							)

						when 'deactivated'
							InactiveSectionsWrapper({
								status, size
								isExpanded: @state.displayDeactivatedSections
								onToggle: @_toggleDisplayDeactivatedSections
							},
								PlanSectionsList
							)


				)
			)

		_toggleDisplayDeactivatedSections: (cb=(->)) ->
			displayDeactivatedSections = @state.displayDeactivatedSections
			@setState {displayDeactivatedSections}, cb

		_toggleDisplayCompletedSections: ->
			displayCompletedSections = @state.displayCompletedSections
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


	InactiveSectionsWrapper = ({status, size, isExpanded, onToggle, children}) ->
			Status = status.charAt(0).toUpperCase() + status.slice(1) # Capitalize

			return R.div({className: "status-#{status}"},
				R.span({
					className: 'inactiveSectionsWrapper'
					onClick: onToggle
				},
					# Rotates 90'CW when expanded
					FaIcon('caret-right', {className: 'expanded' if isExpanded})

					R.strong({}, size)
					" #{Status} "
					Term (
						if size > 1 then 'Sections' else 'Section'
					)
				)

				R.div({className: 'sections'},
					children
				)
			)


	# Create drag-drop context for the PlanView class
	return React.createFactory DragDropContext(HTML5Backend) PlanView


module.exports = {load}