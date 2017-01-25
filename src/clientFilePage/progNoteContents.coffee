# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Presentational components for progress note elements

Term = require '../term'


load = (win) ->
	React = win.React
	R = React.DOM

	ProgEventWidget = require('../progEventWidget').load(win)
	MetricWidget = require('../metricWidget').load(win)
	ExpandingTextArea = require('../expandingTextArea').load(win)

	{showWhen, renderLineBreaks} = require('../utils').load(win)


	ProgNoteContents = (props) ->
		{
			progNote
			progEvents
			eventTypes
			planTargetsById

			isEditing
			dataTypeFilter

			selectBasicUnit
			updateBasicUnitNotes
			updateBasicMetric
			selectPlanSectionTarget
			updatePlanTargetNotes
			updatePlanTargetMetric
			updateProgEvent
		} = props

		R.div({className: 'progNoteContents'},
			(progNote.get('units').map (unit) =>
				unitId = unit.get 'id'

				switch unit.get('type')
					when 'basic'
						BasicUnitView({
							key: unitId
							unit, unitId
							isEditing
							dataTypeFilter
							selectBasicUnit
							updateBasicUnitNotes
							updateBasicMetric
						})
					when 'plan'
						PlanUnitView({
							key: unitId
							unit, unitId
							isEditing
							dataTypeFilter
							planTargetsById
							selectPlanSectionTarget
							updatePlanTargetNotes
							updatePlanTargetMetric
						})
			)

			(if progNote.get('summary')
				SummaryUnitView({
					progNote
					dataTypeFilter
				})
			)

			(unless progEvents.isEmpty()
				EventsView({
					progEvents
					eventTypes
					dataTypeFilter
					isEditing
					updateProgEvent
				})
			)
		)


	BasicUnitView = (props) ->
		if not unit.get('notes')
			return null

		{unit, unitId, dataTypeFilter, isEditing} = props

		R.div({
			className: [
				'basic unit'
				"unitId-#{unitId}"
				'isEditing' if isEditing
				showWhen dataTypeFilter isnt 'events' or isEditing
			].join ' '
			key: unitId
			onClick: props.selectBasicUnit.bind null, unit
		},
			R.h3({}, unit.get('name'))
			R.div({className: 'notes'},
				(if props.isEditing
					ExpandingTextArea({
						value: unit.get('notes')
						onChange: props.updateBasicUnitNotes.bind null, unitId
					})
				else
					if unit.get('notes').includes "***"
						R.span({className: 'starred'},
							renderLineBreaks unit.get('notes')
						)
					else
						renderLineBreaks unit.get('notes')
				)
			)

			(unless unit.get('metrics').isEmpty()
				R.div({className: 'metrics'},
					(unit.get('metrics').map (metric) =>
						MetricWidget({
							isEditable: isEditing
							key: metric.get('id')
							name: metric.get('name')
							definition: metric.get('definition')
							onFocus: props.selectBasicUnit.bind null, unit
							onChange: props.updateBasicMetric.bind null, unitId, metricId
							value: metric.get('value')
						})
					)
				)
			)
		)

	PlanUnitView = (props) ->
		{unit, unitId, dataTypeFilter, isEditing} = props

		R.div({
			className: [
				'plan unit'
				showWhen dataTypeFilter isnt 'events' or isEditing
			].join ' '
			key: unitId
		},
			(unit.get('sections').map (section) =>
				sectionId = section.get('id')

				R.section({key: sectionId},
					R.h2({}, section.get('name'))
					R.div({
						className: [
							'empty'
							showWhen section.get('targets').isEmpty()
						].join ' '
					},
						"This #{Term 'section'} is empty because
						the #{Term 'client'} has no #{Term 'plan targets'}."
					)
					(section.get('targets').map (target) =>
						planTargetsById = props.planTargetsById.map (target) -> target.get('revisions').first()
						targetId = target.get('id')
						# Use the up-to-date name & description for header display
						mostRecentTargetRevision = planTargetsById.get targetId

						R.div({
							key: targetId
							className: [
								'target'
								"targetId-#{targetId}"
								'isEditing' if isEditing
							].join ' '
							onClick: props.selectPlanSectionTarget.bind(null, unit, section, mostRecentTargetRevision)
						},
							R.h3({}, target.get('name'))
							R.div({className: "empty #{showWhen target.get('notes') is '' and not isEditing}"},
								'(blank)'
							)
							R.div({className: 'notes'},
								(if isEditing
									ExpandingTextArea({
										value: target.get('notes')
										onChange: props.updatePlanTargetNotes.bind(
											null,
											unitId, sectionId, targetId
										)
									})
								else
									if target.get('notes').includes "***"
										R.span({className: 'starred'},
											renderLineBreaks target.get('notes').replace(/\*\*\*/g, '')
										)
									else
										renderLineBreaks target.get('notes')
								)
							)
							R.div({className: 'metrics'},
								(target.get('metrics').map (metric) =>
									metricId = metric.get('id')

									MetricWidget({
										isEditable: isEditing
										tooltipViewport: '.entriesListView'
										onChange: props.updatePlanTargetMetric.bind(
											null,
											unitId, sectionId, targetId, metricId
										)
										onFocus: props.selectPlanSectionTarget.bind(null, unit, section, mostRecentTargetRevision)
										key: metric.get('id')
										name: metric.get('name')
										definition: metric.get('definition')
										value: metric.get('value')
									})
								)
							)
						)
					)
				)
			)
		)


	SummaryUnitView = ({progNote, dataTypeFilter}) ->
		R.div({
			className: [
				'basic unit'
				showWhen dataTypeFilter isnt 'events'
			].join ' '
		},
			R.h3({}, "Shift Summary")
			R.div({className: 'notes'},
				renderLineBreaks progNote.get('summary')
			)
		)


	EventsView = ({progEvents, eventTypes, dataTypeFilter, isEditing, updateProgEvent}) ->
		R.div({
			className: [
				'progEvents'
				showWhen not dataTypeFilter or (dataTypeFilter isnt 'targets') or isEditing
			].join ' '
		},
			# Don't need to show the Events header when we're only looking at events
			(if dataTypeFilter isnt 'events' or isEditing
				R.h3({}, Term 'Events')
			)

			(progEvents.map (progEvent, index) =>
				ProgEventWidget({
					key: progEvent.get('id')
					format: 'large'
					progEvent
					eventTypes
					isEditing
					updateProgEvent: updateProgEvent.bind null, index
				})
			)
		)


	return ProgNoteContents

module.exports = {load}
