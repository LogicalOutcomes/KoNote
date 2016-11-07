# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# The Analysis tab on the client file page.
# Provides various tools for visualizing metrics and events.

Async = require 'async'
Imm = require 'immutable'
Moment = require 'moment'
_ = require 'underscore'

Config = require '../config'
Term = require '../term'
Persist = require '../persist'


load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	C3 = win.c3
	React = win.React
	R = React.DOM
	{FaIcon, renderLineBreaks, showWhen, stripMetadata, makeMoment} = require('../utils').load(win)
	{TimestampFormat} = require('../persist/utils')

	Slider = require('../slider').load(win)
	TimeSpanDate = require('./timeSpanDate').load(win)
	Chart = require('./chart').load(win)

	D3TimestampFormat = '%Y%m%dT%H%M%S%L%Z'
	dateDisplayFormat = 'MMM Do - YYYY'


	AnalysisView = React.createFactory React.createClass
		displayName: 'AnalysisView'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				hasEnoughData: null
				daysOfData: null
				selectedMetricIds: Imm.Set()
				chartType: 'line'
				selectedEventTypeIds: Imm.Set()
				highlightedEventTypeId: undefined # null reserved for Other Types
				starredEventTypeIds: Imm.Set()
				excludedTargetIds: Imm.Set()
				timeSpan: null
			}

		# # Leave this here, need for diff-checking renders/vs/state-props
		# componentDidUpdate: (oldProps, oldState) ->
		# 	# Figure out what changed
		# 	for property of @props
		# 		# console.log "property", property
		# 		if @props[property] isnt oldProps[property]
		# 			console.info "#{property} changed"

		# 	for property of @state
		# 		if @state[property] isnt oldState[property]
		# 			console.info "#{property} changed"

		render: ->

			#################### Metric Values/Entries ####################

			# All non-empty metric values
			metricValues = @props.progNoteHistories
			.filter (progNoteHist) -> progNoteHist.last().get('status') is 'default'
			.flatMap (progNoteHist) -> extractMetricsFromProgNoteHistory progNoteHist
			.filter (metricValue) -> metricValue.get('value').trim().length > 0

			# All metric IDs for which this client file has data
			metricIdsWithData = metricValues
			.map (m) -> m.get 'id'
			.toSet()


			#################### Plan Targets & Metrics ####################

			# Replace plan target & metric ids with obj, discard empty / without metric data
			planSectionsWithData = @props.plan.get('sections').map (section) =>

				targets = section.get('targetIds').map (targetId) =>
					# Grab latest target & metric objects
					target = @props.planTargetsById.getIn([targetId, 'revisions']).first()

					metrics = target.get('metricIds')
					.filter (metricId) -> metricIdsWithData.includes metricId
					.map (metricId) => @props.metricsById.get(metricId)

					return target.remove('metricIds').set 'metrics', metrics

				.filterNot (target) ->
					target.get('metrics').isEmpty()

				return section.remove('targetIds').set 'targets', targets

			.filterNot (section) ->
				section.get('targets').isEmpty()

			# Flat map of plan metrics, as {id: metric}
			# TODO: Do we even need this?
			planMetricsById = planSectionsWithData.flatMap (section) ->
				section.get('targets').flatMap (target) ->
					target.get('metrics').map (metric) ->
						return [metric.get('id'), metric]
					.fromEntrySeq().toMap()
				.fromEntrySeq().toMap()
			.fromEntrySeq().toMap()

			# Flat list of unassigned metrics (has data, but since removed from target)
			unassignedMetricsList = metricIdsWithData
			.filterNot (metricId) -> planMetricsById.has metricId
			.map (metricId) => @props.metricsById.get metricId
			.toList()


			#################### ProgEvents ####################

			# TODO: Filter out cancelled prog/globalEvents @ top-level

			# Ensure globalEvents aren't cancelled
			activeGlobalEvents = @props.globalEvents.filter (globalEvent) -> globalEvent.get('status') is 'default'

			# Figure out which progEvents don't have a globalEvent, and ignore cancelled ones
			uniqueProgEvents = @props.progEvents.filterNot (progEvent) ->
				progEventId = progEvent.get('id')
				return progEvent.get('status') isnt 'default' or activeGlobalEvents.find (globalEvent) ->
					globalEvent.get('relatedProgEventId') is progEventId

			allEvents = uniqueProgEvents.concat activeGlobalEvents

			# List of progEvents currently selected
			# 'null' is used to identify un-typed/other progEvents
			selectedProgEvents = allEvents.filter (progEvent) =>
				@state.selectedEventTypeIds.contains (progEvent.get('typeId') or null)

			# We only grab endTimestamp from progEvents that have one
			spannedProgEvents = allEvents.filter (progEvent) -> !!progEvent.get('endTimestamp')

			# Build list of timestamps from progEvents (start & end) & metrics as Unix Timestamps (ms)
			daysOfData = Imm.List()
			.concat allEvents.map (progEvent) ->
				Moment(progEvent.get('startTimestamp'), Persist.TimestampFormat).startOf('day').valueOf()
			.concat spannedProgEvents.map (progEvent) ->
				Moment(progEvent.get('endTimestamp'), Persist.TimestampFormat).startOf('day').valueOf()
			.concat metricValues.map (metric) ->
				# Account for backdate, else normal timestamp
				metricTimestamp = metric.get('backdate') or metric.get('timestamp')
				return Moment(metricTimestamp, Persist.TimestampFormat).startOf('day').valueOf()
			.toOrderedSet()
			.sort()


			#################### Date Range / TimeSpan ####################

			# Determine earliest & latest days
			firstDay = Moment daysOfData.first()
			lastDay = Moment daysOfData.last()
			dayRange = lastDay.diff(firstDay, 'days') + 1

			# Create list of all days as moments
			xTicks = Imm.List([0..dayRange]).map (n) ->
				firstDay.clone().add(n, 'days')

			# Declare default timeSpan
			@defaultTimeSpan = Imm.Map {
				start: xTicks.first()
				end: xTicks.last()
			}

			# Assign default timespan if null
			timeSpan = if not @state.timeSpan? then @defaultTimeSpan else @state.timeSpan

			## TODO:
			## Ensure timeSpan is contained within the actual span of xTicks (days)
			# if timeSpan.get('end').isAfter xTicks.last()
			# 	timeSpan = timeSpan.set 'end', xTicks.last()
			# else if timeSpan.get('start').isBefore xTicks.first()
			# 	timeSpan = timeSpan.set 'start', xTicks.first()

			#################### Event Types ####################

			# Include hovered/highlighted eventTypeId with starred eventTypeIds
			highlightedEventTypeIds = if @state.highlightedEventTypeId isnt undefined
				@state.starredEventTypeIds.add @state.highlightedEventTypeId
			else
				@state.starredEventTypeIds


			# Map out visible progEvents (within timeSpan) by eventTypeId
			visibleProgEvents = selectedProgEvents.filter (progEvent) ->
				endTimestamp = progEvent.get('endTimestamp')
				startMoment = makeMoment progEvent.get('startTimestamp')

				if endTimestamp
					endMoment = makeMoment(endTimestamp)
					return startMoment.isBetween(timeSpan.get('start'), timeSpan.get('end')) or
					endMoment.isBetween(timeSpan.get('start'), timeSpan.get('end')) or
					(startMoment.isBefore(timeSpan.get('start')) and endMoment.isAfter(timeSpan.get('end')))
				else
					return startMoment.isBetween(timeSpan.get('start'), timeSpan.get('end'))

			visibleProgEventsByTypeId = visibleProgEvents.groupBy (progEvent) -> progEvent.get('typeId')

			# Map out visible metric values (within timeSpan) by metric [definition] id
			visibleMetricValues = metricValues.filter (value) ->
				makeMoment(value.get('timestamp')).isBetween timeSpan.get('start'), timeSpan.get('end')

			visibleMetricValuesById = visibleMetricValues.groupBy (value) -> value.get('id')

			# Booleans for the OTHER menu (TODO: Component-alize this stuff!)
			otherEventTypesIsSelected = @state.selectedEventTypeIds.contains null
			otherEventTypesIsPersistent = @state.starredEventTypeIds.contains null
			otherEventTypesIsHighlighted = @state.highlightedEventTypeId is null
			visibleUntypedProgEvents = visibleProgEventsByTypeId.get('')


			#################### ETC ####################

			hasEnoughData = daysOfData.size > 0
			untypedEvents = allEvents.filterNot (progEvent) => !!progEvent.get('typeId')


			return R.div({className: "analysisView"},
				R.div({className: "noData #{showWhen not hasEnoughData}"},
					R.div({},
						R.h1({}, "More Data Needed")
						R.div({},
							"Analytics will show up here once #{Term 'metrics'} or #{Term 'events'}
							have been recorded in a #{Term 'progress note'} for #{@props.clientName}."
						)
					)
				)
				R.div({className: "timeScaleToolbar #{showWhen hasEnoughData}"},
					R.div({className: 'timeSpanContainer'},
						Slider({
							ref: 'timeSpanSlider'
							isRange: true
							timeSpan
							xTicks
							onChange: @_updateTimeSpanDate
						})
						R.div({className: 'dateDisplay'},
							TimeSpanDate({
								date: timeSpan.get('start')
								type: 'start'
								timeSpan
								xTicks
								updateTimeSpanDate: @_updateTimeSpanDate
							})
							TimeSpanDate({
								date: timeSpan.get('end')
								type: 'end'
								timeSpan
								xTicks
								updateTimeSpanDate: @_updateTimeSpanDate
							})
						)
					)
					R.div({className: 'granularContainer'}) # TODO: Make use of this space
				)
				R.div({className: "mainWrapper #{showWhen hasEnoughData}"},
					R.div({className: 'chartContainer'},

						# Fade out un-highlighted regions when exists
						InlineHighlightStyles(highlightedEventTypeIds)

						# Force chart to be re-rendered when tab is opened
						(unless @state.selectedEventTypeIds.isEmpty() and @state.selectedMetricIds.isEmpty()
							Chart({
								ref: 'mainChart'
								progNotes: @props.progNotes
								progEvents: selectedProgEvents
								eventTypes: @props.eventTypes
								metricsById: @props.metricsById
								metricValues
								xTicks
								selectedMetricIds: @state.selectedMetricIds
								chartType: @state.chartType
								timeSpan
								updateMetricColors: @_updateMetricColors
							})
						else
							# Don't render Chart until data points selected
							R.div({className: 'noData'},
								R.div({},
									R.h1({}, "Select Data")
									R.div({},
										"Begin your #{Term 'analysis'} by selecting
										one or more data points from the right panel."
									)
								)
							)
						)
					)
					R.div({className: 'selectionPanel'},
						R.div({className: 'dataType progEvents'},
							progEventsAreSelected = not @state.selectedEventTypeIds.isEmpty()
							allEventTypesSelected = @state.selectedEventTypeIds.size is (@props.eventTypes.size + 1)

							R.h2({
								onClick: @_toggleAllEventTypes.bind null, allEventTypesSelected
							},
								R.span({className: 'helper'}
									"Select "
									if allEventTypesSelected then "None" else "All"
								)
								R.input({
									type: 'checkbox'
									checked: progEventsAreSelected
								})
								Term 'Events'
							)

							(if allEvents.isEmpty()
								R.div({className: 'noData'},
									"No #{Term 'events'} have been recorded yet."
								)
							)

							(unless @props.eventTypes.isEmpty()
								R.div({},
									R.h3({}, Term 'Event Types')
									R.div({className: 'dataOptions'},
										(@props.eventTypes.map (eventType) =>
											eventTypeId = eventType.get('id')

											# TODO: Make this faster
											progEventsWithType = allEvents.filter (progEvent) -> progEvent.get('typeId') is eventTypeId

											visibleProgEvents = visibleProgEventsByTypeId.get(eventTypeId)

											isSelected = @state.selectedEventTypeIds.contains eventTypeId
											isHighlighted = @state.highlightedEventTypeId is eventTypeId
											isPersistent = @state.starredEventTypeIds.contains eventTypeId

											(unless progEventsWithType.isEmpty()
												R.div({
													key: eventTypeId
													className: [
														'checkbox'
														'isHighlighted' if isPersistent
													].join ' '
													onMouseEnter: @_highlightEventType.bind(null, eventTypeId) if isSelected
													onMouseLeave: @_unhighlightEventType.bind(null, eventTypeId) if isHighlighted
												},
													R.label({},
														(if visibleProgEvents?
															R.span({
																className: 'colorKeyCount'
																style:
																	background: eventType.get('colorKeyHex')
															},
																visibleProgEvents.size
															)
														)

														(if isSelected
															FaIcon('star', {
																onClick: @_toggleStarredEventType.bind null, eventTypeId
															})
														)

														R.input({
															type: 'checkbox'
															checked: @state.selectedEventTypeIds.contains eventTypeId
															onChange: @_updateSelectedEventTypes.bind null, eventTypeId
														})
														eventType.get('name')
													)
												)
											)
										)
									)
								)
							)

							(unless untypedEvents.isEmpty()
								R.div({},
									R.h3({}, "Other")
									R.div({className: 'dataOptions'},
										R.div({
											className: [
												'checkbox'
												'isHighlighted' if otherEventTypesIsPersistent
											].join ' '
											onMouseEnter: @_highlightEventType.bind(null, null) if otherEventTypesIsSelected
											onMouseLeave: @_unhighlightEventType.bind(null, null) if otherEventTypesIsHighlighted
										},
											R.label({},
												(if visibleUntypedProgEvents?
													R.span({
														className: 'colorKeyCount'
														style:
															background: '#cadbe5' # Default (other) eventType color
													},
														visibleUntypedProgEvents.size
													)
												)

												(if otherEventTypesIsSelected
													FaIcon('star', {
														onClick: @_toggleStarredEventType.bind null, null
													})
												)

												R.input({
													type: 'checkbox'
													checked: otherEventTypesIsSelected
													onChange: @_updateSelectedEventTypes.bind null, null
												})
												untypedEvents.size
												' '
												Term (if untypedEvents.size is 1 then 'Event' else 'Events')
											)
										)
									)
								)
							)
						)

						R.div({className: 'dataType metrics'},
							metricsAreSelected = not @state.selectedMetricIds.isEmpty()
							allMetricsSelected = Imm.is @state.selectedMetricIds, metricIdsWithData

							R.h2({
								onClick: @_toggleAllMetrics.bind null, allMetricsSelected, metricIdsWithData
							},
								R.span({className: 'helper'}
									"Select "
									if allMetricsSelected then "None" else "All"
								)
								R.input({
									type: 'checkbox'
									checked: metricsAreSelected
								})
								Term 'Metrics'
							)

							R.div({className: 'dataOptions'},
								R.div({className: "chartTypeContainer"},
									"Chart Type: "
									R.label({},
										"Line "
										R.input({
											type: 'checkbox'
											checked: @state.chartType is 'line'
											onChange: @_updateChartType.bind null, 'line'
										})
									)
									R.label({},
										"Spline "
										R.input({
											type: 'checkbox'
											checked: @state.chartType is 'spline'
											onChange: @_updateChartType.bind null, 'spline'
										})
									)
									R.label({},
										"Scatter "
										R.input({
											type: 'checkbox'
											checked: @state.chartType is 'scatter'
											onChange: @_updateChartType.bind null, 'scatter'
										})
									)
								)
								(planSectionsWithData.map (section) =>
									R.div({key: section.get('id')},
										R.h3({}, section.get('name'))
										R.section({key: section.get('id')},

											(section.get('targets').map (target) =>
												targetId = target.get('id')
												targetIsInactive = target.get('status') isnt 'default'

												R.div({
													key: targetId
													className: 'target'
												},
													R.h5({}, target.get('name'))

													# TODO: Extract to component
													(target.get('metrics').map (metric) =>
														metricId = metric.get('id')
														metricIsInactive = targetIsInactive or metric.get('status') isnt 'default'
														visibleValues = visibleMetricValuesById.get metricId
														isSelected = @state.selectedMetricIds.contains metricId
														metricColor = if @state.metricColors? then @state.metricColors["y-#{metric.get('id')}"]

														R.div({
															key: metricId
															className: 'checkbox metric'
														},
															R.label({},
																(if isSelected and visibleValues?
																	R.span({
																		className: 'colorKeyCount circle'
																		style:
																			background: metricColor
																	},
																		visibleValues.size
																	)
																)
																R.input({
																	type: 'checkbox'
																	onChange: @_updateSelectedMetrics.bind null, metricId
																	checked: isSelected
																})
																metric.get('name')
															)
														)
													)
												)
											)
										)
									)
								)
							)
							(unless unassignedMetricsList.isEmpty()
								R.div({},
									R.h3({}, "Inactive")
									R.div({className: 'dataOptions'},
										(unassignedMetricsList.map (metric) =>
											metricId = metric.get('id')
											isSelected = @state.selectedMetricIds.contains metricId
											visibleValues = visibleMetricValuesById.get metricId
											metricColor = if @state.metricColors? then @state.metricColors["y-#{metric.get('id')}"]

											R.div({
												key: metricId
												className: 'checkbox metric'
											},
												R.label({},
													(if isSelected and visibleValues?
														R.span({
															className: 'colorKeyCount circle'
															style:
																background: metricColor
														},
															visibleValues.size
														)
													)
													R.input({
														type: 'checkbox'
														onChange: @_updateSelectedMetrics.bind null, metricId
														checked: isSelected
													})
													metric.get('name')
												)
											)
										)
									)
								)
							)
						)
					)
				)
			)

		_toggleTargetExclusionById: (targetId) ->
			@setState ({excludedTargetIds}) =>
				if excludedTargetIds.contains targetId
					excludedTargetIds = excludedTargetIds.delete targetId
				else
					excludedTargetIds = excludedTargetIds.add targetId

				return {excludedTargetIds}

		_toggleTargetExclusionBySection: (targetIds, sectionHasTargetExclusions) ->
			@setState ({excludedTargetIds}) =>
				if sectionHasTargetExclusions
					excludedTargetIds = excludedTargetIds.subtract targetIds
				else
					excludedTargetIds = excludedTargetIds.union targetIds

				return {excludedTargetIds}

		_updateSelectedEventTypes: (eventTypeId) ->
			if @state.selectedEventTypeIds.contains eventTypeId
				selectedEventTypeIds = @state.selectedEventTypeIds.delete eventTypeId
				# Also remove persistent eventType highlighting if exists
				starredEventTypeIds = @state.starredEventTypeIds.delete eventTypeId
			else
				selectedEventTypeIds = @state.selectedEventTypeIds.add eventTypeId
				starredEventTypeIds = @state.starredEventTypeIds

			# User is still hovering, so make sure it's still transiently-highlighted
			highlightedEventTypeId = eventTypeId

			@setState {selectedEventTypeIds, starredEventTypeIds, highlightedEventTypeId}

		_toggleAllEventTypes: (allEventTypesSelected) ->
			if not allEventTypesSelected
				selectedEventTypeIds = @props.eventTypes
				.map (eventType) -> eventType.get('id') # all eventTypes
				.push(null) # null = progEvents without an eventType
				.toSet()

				starredEventTypeIds = @state.starredEventTypeIds
			else
				# Clear all
				selectedEventTypeIds = @state.selectedEventTypeIds.clear()
				starredEventTypeIds = @state.starredEventTypeIds.clear()

			@setState {selectedEventTypeIds, starredEventTypeIds}

		_highlightEventType: (eventTypeId) ->
			# Ignore persistent eventTypeIds
			return if @state.highlightedEventTypeId is eventTypeId or
			@state.starredEventTypeIds.contains eventTypeId

			highlightedEventTypeId = eventTypeId
			@setState {highlightedEventTypeId}

		_unhighlightEventType: (eventTypeId) ->
			# Ignore persistent eventTypeIds
			return if @state.highlightedEventTypeId isnt eventTypeId or
			@state.starredEventTypeIds.contains eventTypeId

			highlightedEventTypeId = undefined

			@setState {highlightedEventTypeId}

		_toggleStarredEventType: (eventTypeId, event) ->
			event.preventDefault() # Prevents surrounding <label> from stealing the click

			if @state.starredEventTypeIds.includes eventTypeId
				starredEventTypeIds = @state.starredEventTypeIds.delete eventTypeId
			else
				starredEventTypeIds = @state.starredEventTypeIds.add eventTypeId

			@setState {starredEventTypeIds}

		_toggleAllMetrics: (allMetricsSelected, metricIdsWithData) ->
			@setState ({selectedMetricIds}) =>
				if allMetricsSelected
					selectedMetricIds = selectedMetricIds.clear()
				else
					selectedMetricIds = metricIdsWithData

				return {selectedMetricIds}

		_updateChartType: (type) ->
			@setState {chartType: type}

		_updateSelectedMetrics: (metricId) ->
			@setState ({selectedMetricIds}) =>
				if selectedMetricIds.contains metricId
					selectedMetricIds = selectedMetricIds.delete metricId
				else
					selectedMetricIds = selectedMetricIds.add metricId

				return {selectedMetricIds}

		_updateMetricColors: (metricColors) ->
			@setState {metricColors}

		_updateTimeSpanDate: (timeSpan) ->
			@setState {timeSpan}


	InlineHighlightStyles = (eventTypeIds) ->
		return null if eventTypeIds.isEmpty()

		# Selectively exclude highlighted events from opacity change
		notStatements = eventTypeIds
		.map (id) -> ":not(.typeId-#{id})"
		.toJS().join ''

		fillOpacity = 0.15
		styles = "g.c3-region#{notStatements} rect {fill-opacity: #{fillOpacity} !important}"

		return R.style({}, styles)


	extractMetricsFromProgNoteHistory = (progNoteHist) ->
		createdAt = progNoteHist.first().get('timestamp')
		progNote = progNoteHist.last()

		switch progNote.get('type')
			when 'basic'
				# Quick notes don't have metrics
				return Imm.List()
			when 'full'
				return progNote.get('units').flatMap (section) ->
					# Apply backdate as timestamp if exists
					timestamp = progNote.get('backdate') or createdAt
					return extractMetricsFromProgNoteSection section, timestamp
			else
				throw new Error "unknown progNote type: #{JSON.stringify progNote.get('type')}"


	extractMetricsFromProgNoteSection = (section, timestamp) ->
		switch section.get 'type'
			when 'basic'
				return section.get('metrics').map (metric) ->
					Imm.Map {
						id: metric.get 'id'
						timestamp
						value: metric.get 'value'
					}
			when 'plan'
				return section.get('sections').flatMap (section) ->
					section.get('targets').flatMap (target) ->
						target.get('metrics').map (metric) ->
							Imm.Map {
								id: metric.get 'id'
								timestamp
								value: metric.get 'value'
							}
			else
				throw new Error "unknown prognote section type: #{JSON.stringify section.get('type')}"


	return {AnalysisView}


module.exports = {load}