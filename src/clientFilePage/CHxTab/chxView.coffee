# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Main view component for Chx Tab in client file
# Wrapped in main drag-drop context, to re-order sections & topics
# Handles auto-scrolling behaviour

Imm = require 'immutable'

load = (win) ->
	React = win.React
	R = React.DOM
	{findDOMNode} = win.ReactDOM

	{DragDropContext} = win.ReactDnD
	HTML5Backend = win.ReactDnDHTML5Backend

	ChxSection = require('./chxSection').load(win)
	InactiveToggleWrapper = require('./inactiveToggleWrapper').load(win)
	{DropdownButton, MenuItem} = require('../../utils/reactBootstrap').load(win, 'DropdownButton', 'MenuItem')

	{scrollToElement} = require('../../utils').load(win)


	ChxView = React.createClass
		displayName: 'ChxView'
		mixins: [React.addons.PureRenderMixin]
		# TODO: propTypes

		getInitialState: -> {
			displayDeactivatedSections: false
			displayCompletedSections: false
		}

		render: ->
			chxSections = @props.chx.get('sections')

			if chxSections.isEmpty()
				return null

			# Build sections by status, and order them manually into an array
			# TODO: Make this an ordered set or something...
			sectionsByStatus = chxSections.groupBy (s) -> s.get('status')
			sectionsByStatusArray = Imm.List(['default', 'completed', 'deactivated']).map (status) ->
				sectionsByStatus.get(status)

			return R.div({id: 'chxView'},

				(sectionsByStatusArray.map (sections) =>
					# TODO: Remove this in favour of [key, value] (prev. TODO)
					return null if not sections
					status = sections.getIn [0, 'status']
					size = sections.size

					# Build the list of sections
					ChxSectionsList = R.div({
						key: status
						className: 'sections'
					},
						(sections.map (section) =>
							id = section.get('id')
							index = chxSections.indexOf section
							sectionIsInactive = section.get('status') isnt 'default'

							program = @props.programsById.get(section.get('programId'))

							props = Object.assign {}, @props, {
								ref: "section-#{id}"
								key: id
								section, program, id, index
								expandTopic: @_expandTopic
								expandSection: @_expandSection
							}

							return ChxSection(props)
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
								ChxSectionsList

							when 'deactivated'
								InactiveToggleWrapper({
									children: ChxSectionsList
									dataType: 'section'
									status, size
									isExpanded: @state.displayDeactivatedSections
									onToggle: @_toggleDisplayDeactivatedSections
								})

							when 'completed'
								InactiveToggleWrapper({
									children: ChxSectionsList
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

		_expandTopic: (id) ->
			elementId = "topic-#{id}"

			# Account for read-only notice on top if isReadOnly
			additionalOffset = if @props.isReadOnly
				$('#readOnlyNotice').innerHeight() * -1
			else
				0

			additionalOffset += 25 # Add a bit extra for sectionHeader

			# Switch views & select topic, expand groups if needed, scroll!
			@props.collapseAndSelectTopicId id, => @scrollTo(elementId, additionalOffset)

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


	# Create drag-drop context for the ChxView class
	return React.createFactory DragDropContext(HTML5Backend) ChxView


module.exports = {load}
