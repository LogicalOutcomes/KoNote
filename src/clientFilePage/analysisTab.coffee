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
	{FaIcon, renderLineBreaks, showWhen, stripMetadata} = require('../utils').load(win)
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
				targetMetricsById: Imm.Map()
				inactiveMetricIds: Imm.List()
				metricValues: null
				selectedMetricIds: Imm.Set()
				filteredProgEvents: Imm.Set()
				selectedEventTypeIds: Imm.Set()
				excludedTargetIds: Imm.Set()
				xTicks: Imm.List()
				xDays: Imm.List()
				timeSpan: null
			}

		componentDidUpdate: (oldProps, oldState) ->

			# for property of @props
			# 	# console.log "property", property
			# 	if @props[property] isnt oldProps[property]
			# 		console.log "#{property} changed"

			# for property of @state
			# 	if @state[property] isnt oldState[property]
			# 		console.log "#{property} changed"

		render: ->
			console.info "Render"

			# Build targets list as targetId:[metricIds]
			targetMetricsById = @props.plan.get('sections').flatMap (section) =>
				section.get('targetIds').map (targetId) =>
					target = @props.planTargetsById.getIn([targetId, 'revisions']).first()
					return [target.get('id'), target.get('metricIds')]
				.fromEntrySeq().toMap()
			.fromEntrySeq().toMap()

			# Flatten to a single list of targets' metric ids
			targetMetricIdsList = targetMetricsById.toList().flatten(true)

			# All non-empty metric values
			metricValues = @props.progNoteHistories
			.filter (progNoteHist) ->
				# Ignore data from cancelled prognotes
				switch progNoteHist.last().get('status')
					when 'default'
						return true
					when 'cancelled'
						return false
					else
						throw new Error "unknown progNote status: #{progNoteHist.last().get('status')}"
			.flatMap (progNoteHist) ->
				# Extract metrics
				return extractMetricsFromProgNoteHistory progNoteHist
			.filter (metricValue) ->
				# Ignore blank metric values
				return metricValue.get('value').trim().length > 0

			# All metric IDs for which this client file has data
			metricIdsWithData = metricValues
			.map (m) -> m.get 'id'
			.toSet()

			# Build list of inactive metricIds that have data
			inactiveMetricIds = metricIdsWithData.filterNot (metricId) ->
				targetMetricIdsList.contains metricId


			#################### ProgEvents ####################

			# Build set list of progEvent Ids
			progEventIdsWithData = @props.progEvents
			.map (progEvent) -> progEvent.get 'id'
			.toSet()

			# Filter out progEvents that aren't cancelled or excluded
			filteredProgEvents = @props.progEvents
			.concat @props.globalEvents
			.filter (progEvent) =>
				switch progEvent.get('status')
					when 'default'
						return true
					when 'cancelled'
						return false
					else
						throw new Error "unkown progEvent status: #{progEvent.get('status')}"
			.filter (progEvent) =>
				if progEvent.get('typeId')
					@state.selectedEventTypeIds.contains progEvent.get('typeId')
				else
					@state.selectedEventTypeIds.contains null

			# Build list of timestamps from progEvents (start & end) & metrics
			daysOfData = Imm.List()
			.concat filteredProgEvents.map (progEvent) ->
				Moment(progEvent.get('startTimestamp'), Persist.TimestampFormat).startOf('day').valueOf()
			.concat filteredProgEvents.map (progEvent) ->
				Moment(progEvent.get('endTimestamp'), Persist.TimestampFormat).startOf('day').valueOf()
			.concat metricValues.map (metric) ->
				# Account for backdate, else normal timestamp
				metricTimestamp = metric.get('backdate') or metric.get('timestamp')
				return Moment(metricTimestamp, Persist.TimestampFormat).startOf('day').valueOf()
			.toOrderedSet()
			.sort()



			#################### Date Range ####################

			# Determine earliest & latest days
			firstDay = Moment daysOfData.first()
			lastDay = Moment daysOfData.last()
			dayRange = lastDay.diff(firstDay, 'days') + 1

			# Create list of all days as moments
			xTicks = Imm.List([0..dayRange]).map (n) ->
				firstDay.clone().add(n, 'days')

			# Default timespan to full xTicks
			timeSpan = if @state.timeSpan then @state.timeSpan else Imm.Map {
				start: xTicks.first()
				end: xTicks.last()
			}

			hasEnoughData = daysOfData.size > 0
			untypedEvents = @props.progEvents.filterNot (progEvent) => progEvent.get('typeId')

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
							onChange: (event) =>
								# Convert event value (string) to JS numerical array
								timeSpanArray = event.target.value.split(",")
								# Use index values to fetch moment objects from xTicks
								start = xTicks.get Number(timeSpanArray[0])
								end = xTicks.get Number(timeSpanArray[1])

								newTimeSpan = Imm.Map {start, end}
								@setState {timeSpan: newTimeSpan}
							formatter: ([start, end]) =>
								return unless start? and end?
								startTime = Moment(xTicks.get(start)).format('MMM Do')
								endTime = Moment(xTicks.get(end)).format('MMM Do')
								return "#{startTime} - #{endTime}"
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
						# Force chart to be re-rendered when tab is opened
						if not xTicks.isEmpty() and (
							not filteredProgEvents.isEmpty() or
							not @state.selectedMetricIds.isEmpty()
						)
							Chart({
								ref: 'mainChart'
								progNotes: @props.progNotes
								progEvents: filteredProgEvents
								eventTypes: @props.eventTypes
								metricsById: @props.metricsById
								metricValues
								xTicks
								selectedMetricIds: @state.selectedMetricIds
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

							(if @props.progEvents.isEmpty()
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

											R.div({
												className: 'checkbox'
												key: eventTypeId
												style:
													borderRight: "5px solid #{eventType.get('colorKeyHex')}"
											},
												R.label({},
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

							(unless untypedEvents.isEmpty()
								R.div({},
									R.h3({}, "Other")
									R.div({className: 'dataOptions'},
										R.div({className: 'checkbox'},
											R.label({},
												R.input({
													type: 'checkbox'
													checked: @state.selectedEventTypeIds.contains null
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

							R.h3({}, "Plan")
							R.div({className: 'dataOptions'},
								(@props.plan.get('sections').map (section) =>
									R.div({key: section.get('id')},
										R.h4({}, section.get('name'))
										R.section({key: section.get('id')},
											(section.get('targetIds').map (targetId) =>
												target = @props.planTargetsById.getIn([targetId, 'revisions']).first()

												R.div({
													key: targetId
													className: 'target'
												},
													R.h5({}, target.get('name'))

													(targetMetricsById.get(targetId).map (metricId) =>

														metric = @props.metricsById.get(metricId)

														R.div({
															key: metricId
															className: 'checkbox metric'
															style:
																borderRight: (
																	if @state.metricColors?
																		metricColor = @state.metricColors["y-#{metric.get('id')}"]
																		"5px solid #{metricColor}"
																)
														},
															R.label({},
																R.input({
																	type: 'checkbox'
																	onChange: @_updateSelectedMetrics.bind null, metricId
																	checked: @state.selectedMetricIds.contains metricId
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

							(unless @state.inactiveMetricIds.isEmpty()
								R.div({},
									R.h3({}, "Inactive")
									R.div({className: 'dataOptions'},
										(@state.inactiveMetricIds.map (metricId) =>

											metric = @props.metricsById.get(metricId)

											R.div({
												className: 'checkbox metric'
												key: metricId
												style:
													borderRight: (
														if @state.metricColors?
															metricColor = @state.metricColors["y-#{metric.get('id')}"]
															"5px solid #{metricColor}"
													)
											},
												R.label({},
													R.input({
														type: 'checkbox'
														onChange: @_updateSelectedMetrics.bind null, metricId
														checked: @state.selectedMetricIds.contains metricId
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
			@setState ({selectedEventTypeIds}) =>
				if selectedEventTypeIds.contains eventTypeId
					selectedEventTypeIds = selectedEventTypeIds.delete eventTypeId
				else
					selectedEventTypeIds = selectedEventTypeIds.add eventTypeId

				return {selectedEventTypeIds}

		_toggleAllEventTypes: (allEventTypesSelected) ->
			@setState ({selectedEventTypeIds}) =>
				unless allEventTypesSelected
					selectedEventTypeIds = @props.eventTypes
					.map (eventType) -> eventType.get('id') # all evenTypes
					.push(null) # null = progEvents without an eventType
					.toSet()
				else
					selectedEventTypeIds = selectedEventTypeIds.clear()

				return {selectedEventTypeIds}

		_toggleAllMetrics: (allMetricsSelected, metricIdsWithData) ->
			@setState ({selectedMetricIds}) =>
				if allMetricsSelected
					selectedMetricIds = selectedMetricIds.clear()
				else
					selectedMetricIds = metricIdsWithData

				return {selectedMetricIds}

		_updateSelectedMetrics: (metricId) ->
			@setState ({selectedMetricIds}) =>
				if selectedMetricIds.contains metricId
					selectedMetricIds = selectedMetricIds.delete metricId
				else
					selectedMetricIds = selectedMetricIds.add metricId

				return {selectedMetricIds}

		_updateMetricColors: (metricColors) ->
			@setState {metricColors}

		_updateTimeSpanDate: (newDate, type) ->
			return unless @state.timeSpan
			timeSpan = @state.timeSpan.set(type, newDate)
			@setState {timeSpan}

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