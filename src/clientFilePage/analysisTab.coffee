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
				selectedProgEventIds: Imm.Set()
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

			unless Imm.is oldState.excludedTargetIds, @state.excludedTargetIds
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

			# Filter out any cancelled progEvents
			filteredProgEvents = @_filterCancelledProgEvents @props.progEvents			

			# Build set list of progEvent Ids
			progEventIdsWithData = filteredProgEvents
			.map (progEvent) -> progEvent.get 'id'
			.toSet()

			# Build list of timestamps from progEvents (start & end) & metrics
			timestampDays = Imm.List()
			.concat filteredProgEvents.map (progEvent) ->
				Moment(progEvent.get('startTimestamp'), Persist.TimestampFormat).startOf('day').valueOf()
			.concat filteredProgEvents.map (progEvent) ->
				Moment(progEvent.get('endTimestamp'), Persist.TimestampFormat).startOf('day').valueOf()
			.concat metricValues.map (metric) ->
				if metric.get('backdate')
					Moment(metric.get('backdate'), Persist.TimestampFormat).startOf('day').valueOf()
				else
					Moment(metric.get('timestamp'), Persist.TimestampFormat).startOf('day').valueOf()
			# Filter to unique days, and sort
			.toOrderedSet().sort()

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
			}

		_filterCancelledProgEvents: (progEvents) ->
			return progEvents.filter (progEvent) ->
				# Ignore data from cancelled progEvents
				switch progEvent.get('status')
					when 'default'
						return true
					when 'cancelled'
						return false
					else
						throw new Error "unknown progEvent status: #{progEvent.get('status')}"

		render: ->
			hasEnoughData = @state.daysOfData > 0

			# Filter out selectedMetrics that are disabled by excludedTargetIds
			filteredSelectedMetricIds = @state.selectedMetricIds.filterNot @_metricIsExcluded

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
						if @props.isVisible and @_enoughDataToDisplay()
							Chart({
								ref: 'mainChart'
								progNotes: @props.progNotes
								progEvents: @_filterCancelledProgEvents @props.progEvents
								metricsById: @props.metricsById
								metricValues: @state.metricValues
								xTicks: @state.xTicks
								selectedMetricIds: filteredSelectedMetricIds
								selectedProgEventIds: @state.selectedProgEventIds
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
						R.div({className: 'dataType progEvents'}
							R.h2({}, Term 'Events')

							R.div({className: 'dataOptions'},
								R.div({className: 'checkbox selectAll'},
									allProgEventsSelected = Imm.is(
										@state.selectedProgEventIds, @state.progEventIdsWithData
									)

									R.label({},
										R.input({
											type: 'checkbox'
											onChange: @_toggleAllProgEvents.bind null, allProgEventsSelected
											checked: allProgEventsSelected
										})
										"All #{Term 'Events'}"
									)
								)
							)							
						)	
						R.div({className: 'dataType metrics'}
							R.h2({}, Term 'Metrics')
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
												checked: filteredSelectedMetricIds.contains metricId
												disabled: metricIsExcluded
											})
											metric.get('name')
										)
									)
								).toJS()...
								R.div({
									className: [
										"checkbox selectAll"
										showWhen @state.metricIdsWithData.size > 1
									].join ' '
								},
									allMetricsSelected = Imm.is(
										filteredSelectedMetricIds, @state.metricIdsWithData
									)

									R.label({},
										R.input({
											type: 'checkbox'
											onChange: @_toggleAllMetrics.bind null, allMetricsSelected
											checked: allMetricsSelected
										})
										"All #{Term 'Metrics'}"
									)
								)
							)
						)
						R.div({className: 'dataType plan'},
							R.h2({}, Term 'Plan')
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

		_enoughDataToDisplay: ->
			@state.selectedMetricIds.size > 0 or @state.selectedProgEventIds.size > 0

		_toggleAllProgEvents: (allProgEventsSelected) ->
			@setState ({selectedProgEventIds}) =>
				if allProgEventsSelected
					selectedProgEventIds = @state.selectedProgEventIds.clear()
				else
					selectedProgEventIds = @state.progEventIdsWithData

				return {selectedProgEventIds}

		_toggleAllMetrics: (allMetricsSelected) ->
			@setState ({selectedMetricIds}) =>
				if allMetricsSelected
					selectedMetricIds = @state.selectedMetricIds.clear()
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
