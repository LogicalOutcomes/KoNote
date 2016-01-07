# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# The Analysis tab on the client file page.
# Provides various tools for visualizing metrics and events.

Async = require 'async'
Imm = require 'immutable'
Moment = require 'moment'

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
	Chart = require('./chart').load(win)

	D3TimestampFormat = '%Y%m%dT%H%M%S%L%Z'
	TimeGranularities = ['Day', 'Week', 'Month', 'Year']

	AnalysisView = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]
		getInitialState: ->
			return {
				hasEnoughData: null
				daysOfData: null

				targetMetricsById: Imm.Map()
				metricValues: null				
				selectedMetricIds: Imm.Set()
				filteredProgEvents: Imm.Set()
				excludedEventTypeIds: Imm.Set()
				excludedTargetIds: Imm.Set()
				xTicks: Imm.List()
				xDays: Imm.List()
				timeSpan: null

				isGenerating: true
			}

		componentWillMount: ->
			@_generateAnalysis()

		componentDidUpdate: (oldProps, oldState) ->
			# TODO: Simpler indicator of important props change			
			unless Imm.is oldProps.metricsById, @props.metricsById
				@_generateAnalysis()

			unless Imm.is oldProps.progEvents, @props.progEvents
				@_generateAnalysis()

			unless Imm.is oldProps.progNoteHistories, @props.progNoteHistories
				@_generateAnalysis()

			unless Imm.is oldState.excludedEventTypeIds, @state.excludedEventTypeIds
				@_generateAnalysis()

		_generateAnalysis: ->
			console.log "Generating Analysis...."

			# Build targets list as targetId:[metricIds]
			targetMetricsById = @props.plan.get('sections').flatMap (section) =>
				section.get('targetIds').map (targetId) =>
					target = @props.planTargetsById.getIn([targetId, 'revisions']).first()
					return [target.get('id'), target.get('metricIds')]
				.fromEntrySeq().toMap()
			.fromEntrySeq().toMap()

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
				return extractMetricsFromProgNoteHistory progNoteHist
			.filter (metricValue) -> # Remove blank metrics
				return metricValue.get('value').trim().length > 0

			# All metric IDs for which this client file has data
			metricIdsWithData = metricValues
			.map (m) -> m.get 'id'
			.toSet()

			# Build set list of progEvent Ids
			progEventIdsWithData = @props.progEvents
			.map (progEvent) -> progEvent.get 'id'
			.toSet()

			# Filter out progEvents that aren't cancelled or excluded
			filteredProgEvents = @props.progEvents
			.filter (progEvent) =>				
				switch progEvent.get('status')
					when 'default'
						return true
					when 'cancelled'
						return false
					else
						throw new Error "unkown progEvent status: #{progEvent.get('status')}"
			.filterNot (progEvent) =>
				if progEvent.get('typeId')
					@state.excludedEventTypeIds.contains progEvent.get('typeId')
				else
					@state.excludedEventTypeIds.contains null

			# Build list of timestamps from progEvents (start & end) & metrics
			timestampDays = Imm.List()
			.concat filteredProgEvents.map (progEvent) ->
				Moment(progEvent.get('startTimestamp'), Persist.TimestampFormat).startOf('day').valueOf()
			.concat filteredProgEvents.map (progEvent) ->
				Moment(progEvent.get('endTimestamp'), Persist.TimestampFormat).startOf('day').valueOf()
			.concat metricValues.map (metric) ->
				# Account for backdate, else normal timestamp
				metricTimestamp = metric.get('backdate') or metric.get('timestamp')
				return Moment(metricTimestamp, Persist.TimestampFormat).startOf('day').valueOf()
			.toOrderedSet().sort() # Filter to unique days, and sort

			# Determine earliest & latest days
			firstDay = Moment timestampDays.first()
			lastDay = Moment timestampDays.last()
			dayRange = lastDay.diff(firstDay, 'days') + 1

			# Create list of all days as moments
			xTicks = Imm.List([0..dayRange]).map (n) ->
				firstDay.clone().add(n, 'days')

			# Synchronous to ensure this happens before render
			@setState => {
				targetMetricsById
				xDays: xTicks
				daysOfData: timestampDays.size
				timeSpan: [0, xTicks.size - 1]
				xTicks
				metricIdsWithData, metricValues
				progEventIdsWithData
				filteredProgEvents
			}		

		render: ->
			hasEnoughData = @state.daysOfData > 0

			# Filter out selectedMetrics that are disabled by excludedTargetIds
			selectedMetricIds = @state.selectedMetricIds.filterNot @_metricIsExcluded

			return R.div({className: "view analysisView #{showWhen @props.isVisible}"},
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
					if @props.isVisible
						R.div({className: 'timeSpanContainer'},
							Slider({
								ref: 'timeSpanSlider'
								isEnabled: true
								tooltip: true
								isRange: true
								defaultValue: [0, @state.xTicks.size]
								ticks: @state.xTicks.pop().toJS()
								onChange: @_updateTimeSpan
								formatter: ([start, end]) =>
									startTime = Moment(@state.xTicks.get(start)).format('Do MMM')
									endTime = Moment(@state.xTicks.get(end)).format('Do MMM')
									return "#{startTime} - #{endTime}"
							})
							R.div({className: 'valueDisplay'},
								(@state.timeSpan.map (index) =>
									date = Moment(@state.xTicks.get(index)).format('MMM Do - YYYY')
									return R.div({key: index},
										R.span({}, date)
									)
								)
							)
					)
					# TODO: Make use of this space
					R.div({className: 'granularContainer'})
				)
				R.div({className: "mainWrapper #{showWhen hasEnoughData}"},
					R.div({className: 'chartContainer'},
						# Force chart to be re-rendered when tab is opened
						if @props.isVisible and (
							not @state.excludedEventTypeIds.isEmpty() or
							not selectedMetricIds.isEmpty()
						)
							Chart({
								ref: 'mainChart'
								progNotes: @props.progNotes
								progEvents: @state.filteredProgEvents
								metricsById: @props.metricsById
								metricValues: @state.metricValues
								xTicks: @state.xTicks
								selectedMetricIds
								timeSpan: @state.timeSpan
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
							console.log "@state.excludedEventTypeIds", @state.excludedEventTypeIds.toJS(), @state.excludedEventTypeIds.isEmpty()
							allProgEventsSelected = @state.excludedEventTypeIds.isEmpty()

							R.h2({
								className: 'allSelected' if allProgEventsSelected
								onClick: @_toggleAllEventTypes.bind null, allProgEventsSelected
							}, Term 'Event Types')

							R.div({className: 'dataOptions'},
								(@props.eventTypes.map (eventType) =>
									eventTypeId = eventType.get('id')

									R.div({
										className: 'checkbox'
										key: eventTypeId										
									},
										R.label({},
											R.input({
												type: 'checkbox'
												checked: not @state.excludedEventTypeIds.contains eventTypeId
												onChange: @_toggleEventTypeExclusion.bind null, eventTypeId
											})
											eventType.get('name')
										)
									)
								)

								R.div({className: 'checkbox'},
									R.label({},
										R.input({
											type: 'checkbox'
											checked: not @state.excludedEventTypeIds.contains null
											onChange: @_toggleEventTypeExclusion.bind null, null
										})
										"(No #{Term 'event type'})"
									)
								)
							)							
						)

						R.div({className: 'dataType plan'},
							R.h2({

							}, "#{Term 'Plan'} #{Term 'Metrics'}")

							R.div({className: 'dataOptions'},
								(@props.plan.get('sections').map (section) =>
									targetIds = section.get('targetIds')

									sectionHasTargetExclusions = targetIds.some (id) =>
										@state.excludedTargetIds.contains id

									R.section({key: section.get('id')},
										R.div({className: 'checkbox'},
											R.label({},
												R.input({
													type: 'checkbox'
													onChange: @_toggleTargetExclusionBySection.bind(
														null, targetIds, sectionHasTargetExclusions
													)
													checked: not sectionHasTargetExclusions
												})
												section.get('name')
											)
										)
										(section.get('targetIds').map (targetId) =>
											target = @props.planTargetsById.getIn([targetId, 'revisions']).first()
											targetIsExcluded = @state.excludedTargetIds.contains targetId

											R.div({className: 'checkbox target'},
												R.label({},
													R.input({
														type: 'checkbox'
														onChange: @_toggleTargetExclusionById.bind null, targetId
														checked: not targetIsExcluded
													})
													target.get('name')
												)
											)
										)
									)
								)
							)
						)

						R.div({className: 'dataType metrics'}
							allMetricsSelected = Imm.is(
								selectedMetricIds, @state.metricIdsWithData
							)

							R.h2({
								className: 'allSelected' if allMetricsSelected
								onClick: @_toggleAllMetrics.bind null, allMetricsSelected
							}, "Other #{Term 'Metrics'}")

							R.div({className: 'dataOptions'},
								(@state.metricIdsWithData.map (metricId) =>
									metric = @props.metricsById.get(metricId)
									metricIsExcluded = @_metricIsExcluded metricId

									R.div({
										className: [
											'checkbox'
											'excluded' if metricIsExcluded
										].join ' '
										key: metricId
									},
										R.label({},
											R.input({
												ref: metric.get 'id'
												type: 'checkbox'
												onChange: @_updateSelectedMetrics.bind null, metricId
												checked: selectedMetricIds.contains metricId
												disabled: metricIsExcluded
											})
											metric.get('name')
										)
									)
								).toJS()...
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

		_toggleEventTypeExclusion: (eventTypeId) ->
			@setState ({excludedEventTypeIds}) =>
				if excludedEventTypeIds.contains eventTypeId
					excludedEventTypeIds = excludedEventTypeIds.delete eventTypeId
				else
					excludedEventTypeIds = excludedEventTypeIds.add eventTypeId

				return {excludedEventTypeIds}

		_toggleAllEventTypes: (allEventTypesSelected) ->
			@setState ({excludedEventTypeIds}) =>
				if allEventTypesSelected
					excludedEventTypeIds = @props.eventTypes
					.map (eventType) -> eventType.get('id') # all evenTypes
					.push(null) # null = progEvents without an eventType
					.toSet()
				else
					excludedEventTypeIds = excludedEventTypeIds.clear()

				return {excludedEventTypeIds}

		_toggleAllMetrics: (allMetricsSelected) ->
			@setState ({selectedMetricIds}) =>
				if allMetricsSelected
					selectedMetricIds = selectedMetricIds.clear()
				else
					selectedMetricIds = @state.metricIdsWithData

				return {selectedMetricIds}

		_updateSelectedMetrics: (metricId) ->
			@setState ({selectedMetricIds}) =>
				if selectedMetricIds.contains metricId
					selectedMetricIds = selectedMetricIds.delete metricId
				else
					selectedMetricIds = selectedMetricIds.add metricId

				return {selectedMetricIds}

		_metricIsExcluded: (metricId) ->
			targetId = @state.targetMetricsById.findKey (target) =>
				target.contains metricId
			
			return targetId? and @state.excludedTargetIds.contains(targetId)

		_updateTimeSpan: (event) ->
			timeSpan = event.target.value.split(",")
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
