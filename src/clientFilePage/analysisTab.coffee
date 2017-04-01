# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# The Analysis tab on the client file page.
# Provides various tools for visualizing metrics and events.

Imm = require 'immutable'
Moment = require 'moment'
Fs = require 'graceful-fs'
Path = require 'path'

Config = require '../config'
Term = require '../term'


load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM
	{FaIcon, showWhen} = require('../utils').load(win)
	{TimestampFormat} = require('../persist/utils')
	TimeSpanDate = require('./timeSpanDate').load(win)
	TimeSpanToolbar = require('./timeSpanToolbar').load(win)
	Chart = require('./chart').load(win)


	AnalysisView = React.createFactory React.createClass
		displayName: 'AnalysisView'

		shouldComponentUpdate: (newProps, newState) ->
			# Only run shallowCompare/PureRenderMixin when the tab is visible
			return false unless newProps.isVisible

			React.addons.shallowCompare @, newProps, newState

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

			# Ensure globalEvents aren't cancelled
			activeGlobalEvents = @props.globalEvents.filter (globalEvent) -> globalEvent.get('status') is 'default'

			# Figure out which progEvents don't have a globalEvent, and ignore cancelled ones
			uniqueProgEvents = @props.progEvents.filterNot (progEvent) ->
				progEventId = progEvent.get('id')
				return progEvent.get('status') isnt 'default' or activeGlobalEvents.find (globalEvent) ->
					globalEvent.get('relatedProgEventId') is progEventId

			allEvents = uniqueProgEvents.concat activeGlobalEvents

			# We only grab endTimestamp from progEvents that have one
			spannedProgEvents = allEvents.filter (progEvent) -> !!progEvent.get('endTimestamp')


			#################### Date Range / TimeSpan ####################

			# Build list of timestamps from progEvents (start & end) & metrics
			daysOfData = Imm.List()
			.concat allEvents.map (progEvent) ->
				progEvent.get('startTimestamp')
			.concat spannedProgEvents.map (progEvent) ->
				progEvent.get('endTimestamp')
			.concat metricValues.map (metric) ->
				# Account for backdate, else normal timestamp
				metricTimestamp = metric.get('backdate') or metric.get('timestamp')
				return metricTimestamp
			.toOrderedSet()
			.sort()

			# Determine earliest & latest days
			firstDay = Moment daysOfData.first(), TimestampFormat
			lastDay = Moment daysOfData.last(), TimestampFormat
			dayRange = lastDay.diff(firstDay, 'days') + 1

			# Create list of all days as moments
			xTicks = Imm.List([0..dayRange]).map (n) ->
				firstDay.clone().add(n, 'days')

			# Declare default timeSpan
			# Confirm we have enough data and set to 1 month
			if xTicks.size > 0 and xTicks.last().clone().subtract(1, "month").isSameOrAfter(xTicks.first())
				defaultTimeSpan = Imm.Map {
					start: xTicks.last().clone().subtract(1, "month")
					end: xTicks.last()
				}
			else
				defaultTimeSpan = Imm.Map {
					start: xTicks.first()
					end: xTicks.last()
				}


			AnalysisViewUi(Object.assign {}, @props, {
				metricValues, metricIdsWithData
				planSectionsWithData, planMetricsById, unassignedMetricsList
				activeGlobalEvents, uniqueProgEvents, allEvents, spannedProgEvents
				daysOfData, firstDay, lastDay, dayRange, xTicks, defaultTimeSpan
			})


	AnalysisViewUi = React.createFactory React.createClass
		displayName: 'AnalysisViewUi'

		getInitialState: ->
			return {
				daysOfData: null
				selectedMetricIds: Imm.Set()
				chartType: 'line'
				selectedEventTypeIds: Imm.Set()
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

			{
				metricValues, metricIdsWithData
				planSectionsWithData, planMetricsById, unassignedMetricsList
				activeGlobalEvents, uniqueProgEvents, allEvents, spannedProgEvents
				daysOfData, firstDay, lastDay, dayRange, xTicks, defaultTimeSpan
			} = @props

			# List of progEvents currently selected
			# 'null' is used to identify un-typed/other progEvents
			selectedProgEvents = allEvents.filter (progEvent) =>
				@state.selectedEventTypeIds.contains (progEvent.get('typeId') or null)

			# Assign default timespan if null
			timeSpan = if not @state.timeSpan? then defaultTimeSpan else @state.timeSpan


			#################### Event Types ####################

			# Map out visible progEvents (within timeSpan) by eventTypeId
			visibleProgEvents = allEvents.filter (progEvent) ->
				startTimestamp = Moment progEvent.get('startTimestamp'), TimestampFormat
				endTimestamp = Moment progEvent.get('endTimestamp'), TimestampFormat

				if endTimestamp
					# Start of event is visible [--]----
					return startTimestamp.isBetween(timeSpan.get('start'), timeSpan.get('end'), null, '[]') or # Inclusive
					# End of event is visible ----[--]
					endTimestamp.isBetween(timeSpan.get('start'), timeSpan.get('end'), null, '[]') or # Inclusive
					# Middle of event is visible --[--]--
					(startTimestamp.isSameOrBefore(timeSpan.get('start')) and endTimestamp.isSameOrAfter(timeSpan.get('end')))
				else
					return startTimestamp.isBetween(timeSpan.get('start'), timeSpan.get('end'), null, '[]') # Inclusive

			visibleProgEventsByTypeId = visibleProgEvents.groupBy (progEvent) -> progEvent.get('typeId')

			# Map out visible metric values (within timeSpan) by metric [definition] id
			visibleMetricValues = metricValues.filter (value) ->
				Moment(value.get('timestamp'), TimestampFormat).isBetween(timeSpan.get('start'), timeSpan.get('end'), null, '[]') # Inclusive

			visibleMetricValuesById = visibleMetricValues.groupBy (value) -> value.get('id')

			# Booleans for the OTHER menu (TODO: Component-alize this stuff!)
			otherEventTypesIsSelected = @state.selectedEventTypeIds.contains null
			otherEventTypesIsPersistent = @state.starredEventTypeIds.contains null
			visibleUntypedProgEvents = visibleProgEventsByTypeId.get('') or Imm.List()

			# Establish event types selections for side menu
			untypedEvents = allEvents.filter (e) -> not e.get('typeId')

			eventTypesWithData = @props.eventTypes
			.filter (t) -> allEvents.some (e) -> e.get('typeId') is t.get('id')
			.sortBy (t) -> t.get('name')

			progEventsAreSelected = not @state.selectedEventTypeIds.isEmpty()
			availableEventTypes = eventTypesWithData.size + (if untypedEvents.isEmpty() then 0 else 1)
			allEventTypesSelected = @state.selectedEventTypeIds.size is availableEventTypes


			return R.div({className: "analysisView"},
				R.div({className: "noData #{showWhen not daysOfData.size > 0}"},
					R.div({},
						R.h1({}, "More Data Needed")
						R.div({},
							"Analytics will show up here once #{Term 'metrics'} or #{Term 'events'}
							have been recorded in a #{Term 'progress note'}."
						)
					)
				)
				(if daysOfData.size > 0
					R.div({className: "mainWrapper"},
						R.div({className: "leftPanel"},
							R.div({className: "timeScaleToolbar #{showWhen daysOfData.size > 0}"},
								R.div({className: 'timeSpanContainer'},
									R.div({className: 'dateDisplay'},
										TimeSpanDate({
											date: timeSpan.get('start')
											type: 'start'
											timeSpan
											xTicks
											updateTimeSpan: @_updateTimeSpan
										})
										TimeSpanToolbar({
											updateTimeSpan: @_updateTimeSpan
											timeSpan
											lastDay
											firstDay
											dayRange
										})
										TimeSpanDate({
											date: timeSpan.get('end')
											type: 'end'
											timeSpan
											xTicks
											updateTimeSpan: @_updateTimeSpan
										})
									)
								)
								R.div({className: 'granularContainer'}) # TODO: Make use of this space
							)
							R.div({className: 'chartContainer'},

								# Fade out un-highlighted regions when exists
								InlineHighlightStyles({
									ref: 'inlineHighlightStyles'
									starredEventTypeIds: @state.starredEventTypeIds
								})

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
										updateSelectedMetrics: @_updateSelectedMetrics
										chartType: @state.chartType
										timeSpan
										updateMetricColors: @_updateMetricColors
										updateTimeSpan: @_updateTimeSpan
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
							(unless planSectionsWithData.isEmpty()
								R.div({className: "chartOptionsContainer"},
									R.div({},
										R.button({
											className: 'btn btn-default printBtn'
											onClick: @_printPNG
											title: "Print"
										},
											FaIcon('print')
											" Print"
										)
										R.button({
											className: 'btn btn-default printBtn'
											onClick: @_savePNG
											title: "Save as PNG"
										},
											FaIcon('download')
											" Export"
										)
										# Hidden input for file saving
										R.input({
											ref: 'nwsaveas'
											className: 'hidden'
											type: 'file'
										})
									)
									R.div({},
										"Metrics Chart Type: "

										R.label({},
											"Line "
											R.input({
												type: 'checkbox'
												checked: @state.chartType is 'line'
												onChange: @_updateChartType.bind null, 'line'
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
								)
							)
						)

						R.div({className: 'selectionPanel'},

							R.div({className: 'dataType progEvents'},

								(if allEvents.isEmpty()
									R.h2({className: 'noEventPoints'},
										"(No #{Term 'events'} recorded)"
									)
								else
									R.h2({onClick: @_toggleAllEventTypes.bind null, allEventTypesSelected, eventTypesWithData},
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
								)

								(unless eventTypesWithData.isEmpty()
									R.div({},
										R.h3({}, Term 'Event Types')
										R.div({className: 'dataOptions'},
											(eventTypesWithData.map (eventType) =>
												eventTypeId = eventType.get('id')

												# TODO: Make this faster
												progEventsWithType = allEvents.filter (progEvent) -> progEvent.get('typeId') is eventTypeId
												visibleProgEvents = visibleProgEventsByTypeId.get(eventTypeId) or Imm.List()

												isSelected = @state.selectedEventTypeIds.contains eventTypeId
												isPersistent = @state.starredEventTypeIds.contains eventTypeId

												(unless progEventsWithType.isEmpty()
													R.div({
														key: eventTypeId
														className: [
															'checkbox'
															'isHighlighted' if isPersistent
														].join ' '
														onMouseEnter: @_highlightEventType.bind(null, eventTypeId) if isSelected
														onMouseLeave: @_unhighlightEventType.bind(null, eventTypeId) if isSelected
													},
														R.label({},
															ColorKeyCount({
																isSelected
																colorKeyHex: eventType.get('colorKeyHex')
																count: visibleProgEvents.size
															})

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
										R.h3({},
											if not eventTypesWithData.isEmpty() then "Untyped" else " "
										)
										R.div({className: 'dataOptions'},
											R.div({
												className: [
													'checkbox'
													'isHighlighted' if otherEventTypesIsPersistent
												].join ' '
												onMouseEnter: @_highlightEventType.bind(null, null) if otherEventTypesIsSelected
												onMouseLeave: @_unhighlightEventType.bind(null, null) if otherEventTypesIsSelected
											},
												R.label({},
													ColorKeyCount({
														isSelected: otherEventTypesIsSelected
														colorKeyHex: '#cadbe5'
														count: visibleUntypedProgEvents.size
													})

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

								(if planSectionsWithData.isEmpty()
									R.h2({className: 'noMetricPoints'},
										"(No #{Term 'metrics'} recorded)"
									)
								else
									R.h2({onClick: @_toggleAllMetrics.bind null, allMetricsSelected, metricIdsWithData},
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
								)

								(unless planSectionsWithData.isEmpty()
									R.div({className: 'dataOptions'},
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
																visibleValues = visibleMetricValuesById.get(metricId) or Imm.List()
																isSelected = @state.selectedMetricIds.contains metricId
																metricColor = if @state.metricColors? then @state.metricColors["y-#{metric.get('id')}"]

																R.div({
																	key: metricId
																	className: 'checkbox metric'
																},
																	R.label({},
																		ColorKeyCount({
																			isSelected
																			className: 'circle'
																			colorKeyHex: metricColor
																			count: visibleValues.size
																		})
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
								(unless unassignedMetricsList.isEmpty()
									R.div({},
										R.h3({}, "Inactive")
										R.div({className: 'dataOptions'},
											(unassignedMetricsList.map (metric) =>
												metricId = metric.get('id')
												isSelected = @state.selectedMetricIds.contains metricId
												visibleValues = visibleMetricValuesById.get(metricId) or Imm.List()
												metricColor = if @state.metricColors? then @state.metricColors["y-#{metric.get('id')}"]

												R.div({
													key: metricId
													className: 'checkbox metric'
												},
													R.label({},
														ColorKeyCount({
															isSelected
															className: 'circle'
															colorKeyHex: metricColor
															count: visibleValues.size
														})
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
				@_unhighlightEventType eventTypeId
			else
				selectedEventTypeIds = @state.selectedEventTypeIds.add eventTypeId
				starredEventTypeIds = @state.starredEventTypeIds

			# User is still hovering, so make sure it's still transiently-highlighted
			@_highlightEventType(eventTypeId)

			@setState {selectedEventTypeIds, starredEventTypeIds}

		_toggleAllEventTypes: (allEventTypesSelected, eventTypesWithData) ->
			if not allEventTypesSelected
				selectedEventTypeIds = eventTypesWithData
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
			@refs.inlineHighlightStyles.add eventTypeId

		_unhighlightEventType: (eventTypeId) ->
			@refs.inlineHighlightStyles.remove eventTypeId

		_toggleStarredEventType: (eventTypeId, event) ->
			event.preventDefault() # Prevents surrounding <label> from stealing the click

			if @state.starredEventTypeIds.includes eventTypeId
				starredEventTypeIds = @state.starredEventTypeIds.delete eventTypeId
				# Make the un-starring look immediate
				@_unhighlightEventType eventTypeId
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

		_savePNG: ->
			$(@refs.nwsaveas)
			.off()
			.val('')
			.attr('nwsaveas', "analysis")
			.attr('accept', ".png")
			.on('change', (event) =>
				# png as base64string
				nw.Window.get(win).capturePage ((base64string) ->
					Fs.writeFile event.target.value, base64string, 'base64', (err) ->
						if err
							Bootbox.alert """
								An error occurred.  Please check your network connection and try again.
							"""
							return
						return
				),
					format: 'png'
					datatype: 'raw'
			)
			.click()

		_printPNG: ->
			nw.Window.get(win).capturePage ((base64string) ->
				Fs.writeFile Path.join(Config.backend.dataDirectory, '_tmp', 'analysis.png'), base64string, 'base64', (err) ->
					if err
						Bootbox.alert """
							An error occurred.  Please check your network connection and try again.
						"""
						return
					nw.Window.open Path.join(Config.backend.dataDirectory, '_tmp', 'analysis.png'), {
						focus: false
						show: true
						width: 850
						height: 1100
					}, (pngWindow) =>
						pngWindow.on 'loaded', =>
							pngWindow.print({
								autoprint: false
								headerFooterEnabled: Config.printHeaderFooterEnabled
								headerString: Config.printHeader
								footerString: Config.printFooter
							})
							pngWindow.hide()
							# cleanup
							Fs.unlink Path.join(Config.backend.dataDirectory, '_tmp', 'analysis.png'), (err) ->
								if err
									console.error err
									return
								return
							pngWindow.close()
			),
				format: 'png'
				datatype: 'raw'


		_updateSelectedMetrics: (metricId) ->
			@setState ({selectedMetricIds}) =>
				if selectedMetricIds.contains metricId
					selectedMetricIds = selectedMetricIds.delete metricId
				else
					selectedMetricIds = selectedMetricIds.add metricId

				return {selectedMetricIds}

		_updateMetricColors: (metricColors) ->
			@setState {metricColors}

		_updateTimeSpan: (timeSpan) ->
			@setState {timeSpan}


	InlineHighlightStyles = React.createFactory React.createClass
		displayName: 'InlineHighlightStyles'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: -> {additionalEventTypeId: undefined}

		add: (additionalEventTypeId) ->
			return if @state.additionalEventTypeId is additionalEventTypeId
			@setState {additionalEventTypeId}

		remove: (additionalEventTypeId) ->
			return if @state.additionalEventTypeId isnt additionalEventTypeId
			@setState {additionalEventTypeId: undefined}

		render: ->
			return null if @props.starredEventTypeIds.isEmpty() and @state.additionalEventTypeId is undefined

			eventTypeIds = if @state.additionalEventTypeId isnt undefined
				@props.starredEventTypeIds.add @state.additionalEventTypeId
			else
				@props.starredEventTypeIds

			# Selectively exclude highlighted events from opacity change
			notStatements = eventTypeIds
			.map (id) -> ":not(.typeId-#{id})"
			.toJS().join ''

			fillOpacity = 0.15
			styles = "g.c3-region#{notStatements} {fill-opacity: #{fillOpacity} !important; stroke-opacity: #{fillOpacity}}"

			return R.style({}, styles)


	ColorKeyCount = ({isSelected, className, colorKeyHex, count}) ->
		R.span({
			className: [
				'colorKeyCount'
				className
				'isSelected' if isSelected
			].join ' '
			style:
				background: colorKeyHex if isSelected
		},
			count
		)


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
