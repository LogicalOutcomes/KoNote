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

	D3TimestampFormat = '%Y%m%dT%H%M%S%L%Z'
	TimeGranularities = ['Day', 'Week', 'Month', 'Year']

	AnalysisView = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]
		getInitialState: ->
			return {
				hasEnoughData: null
				daysOfData: null

				metricValues: null				
				selectedMetricIds: Imm.Set()
				selectedProgEventIds: Imm.Set()
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

		_generateAnalysis: ->			
			console.log "Generating Analysis...."

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
						throw new Error "unknown prognote status: #{progNoteHist.last().get('status')}"
			.flatMap (progNoteHist) ->
				return extractMetricsFromProgNoteHistory progNoteHist
			.filter (metricValue) -> # remove blank metrics
				return metricValue.get('value').trim().length > 0

			# All metric IDs for which this client file has data
			metricIdsWithData = metricValues
			.map (m) -> m.get 'id'
			.toSet()

			# All event IDs
			progEventIdsWithData = @props.progEvents
			.map (e) -> e.get 'id'
			.toSet()

			# Build list of timestamps from progEvents (start & end) & metrics
			timestampDays = Imm.List()
			.concat @props.progEvents.map (progEvent) ->
				Moment(progEvent.get('startTimestamp'), Persist.TimestampFormat).startOf('day').valueOf()
			.concat @props.progEvents.map (progEvent) ->
				Moment(progEvent.get('endTimestamp'), Persist.TimestampFormat).startOf('day').valueOf()
			.concat metricValues.map (metric) ->
				Moment(metric.get('timestamp'), Persist.TimestampFormat).startOf('day').valueOf()
			.concat metricValues.map (metric) ->
				Moment(metric.get('backdate'), Persist.TimestampFormat).startOf('day').valueOf()
			# Filter to unique days, and sort
			.toOrderedSet().sort()

			# Determine earliest & latest days
			firstDay = Moment timestampDays.first()
			lastDay = Moment timestampDays.last()
			dayRange = lastDay.diff(firstDay, 'days') + 1

			# Create list of all days as moments
			xTicks = Imm.List([0..dayRange]).map (n) ->
				firstDay.clone().add(n, 'days')

			@setState => {
				xDays: xTicks
				daysOfData: timestampDays.size
				timeSpan: [0, xTicks.size - 1]
				xTicks
				metricIdsWithData, metricValues
				progEventIdsWithData
			}

		render: ->
			hasEnoughData = @state.daysOfData >= Config.analysis.minDaysOfData

			return R.div({className: "view analysisView #{showWhen @props.isVisible}"},
				R.div({className: "noData #{showWhen not hasEnoughData}"},
					R.div({},
						R.h1({}, "More Data Needed")
						R.div({},
							"Sorry, #{Config.analysis.minDaysOfData - @state.daysOfData} 
							more days of #{Term 'progress notes'} containing 
							#{Term 'metrics'} or #{Term 'events'} 
							are required before I can chart anything meaningful here."
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
								progEvents: @props.progEvents
								metricsById: @props.metricsById
								metricValues: @state.metricValues
								xTicks: @state.xTicks
								selectedMetricIds: @state.selectedMetricIds	
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

									R.div({className: 'checkbox'},
										R.label({},
											R.input({
												ref: metric.get 'id'
												type: 'checkbox'
												onChange: @_updateSelectedMetrics.bind null, metricId
												checked: @state.selectedMetricIds.contains metricId
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
										@state.selectedMetricIds, @state.metricIdsWithData
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
					)
				)
			)

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

		_updateTimeSpan: (event) ->
			timeSpan = event.target.value.split(",")
			@setState {timeSpan}


	Chart = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				progEventRegions: Imm.List()
			}

		render: ->
			return R.div({className: 'chartInner'},
				R.div({
					id: 'eventInfo'
					ref: 'eventInfo'
				},
					R.div({className: 'title'})
					R.div({className: 'info'}
						R.div({className: 'description'})
						R.div({className: 'timeSpan'},
							R.div({className: 'start'})
							R.div({className: 'end'})
						)
					)
				)
				R.div({
					className: "chart"
					ref: 'chartDiv'
				})
			)

		componentDidUpdate: (oldProps, oldState) ->
			# TODO: Sort out repetition here, like parent component

			# Update selected metrics?
			sameSelectedMetrics = Imm.is @props.selectedMetricIds, oldProps.selectedMetricIds
			unless sameSelectedMetrics
				@_refreshSelectedMetrics()

			# Update selected progEvents?
			sameSelectedProgEvents = Imm.is @props.selectedProgEventIds, oldProps.selectedProgEventIds
			unless sameSelectedProgEvents
				@_refreshSelectedProgEvents()

			# Update selected progNotes?
			sameMetricValues = Imm.is @props.metricValues, oldProps.metricValues
			unless sameMetricValues
				@_refreshSelectedProgEvents()

			# Update timeSpan?
			sameTimeSpan = @props.timeSpan is oldProps.timeSpan
			unless sameTimeSpan
				@_chart.axis.min {x: @props.xTicks.get @props.timeSpan[0]}
				@_chart.axis.max {x: @props.xTicks.get @props.timeSpan[1]}

				
		componentDidMount: ->			
			@_generateChart()
			@_refreshSelectedMetrics()
			@_refreshSelectedProgEvents()

		_generateChart: ->
			console.log "Generating Chart...."
			# Create a Map from metric ID to data series,
			# where each data series is a sequence of [x, y] pairs
			dataSeries = @props.metricValues
			.groupBy (metricValue) -> # group by metric
				return metricValue.get('id')
			.map (metricValues) -> # for each data series
				return metricValues.map (metricValue) -> # for each data point
					# [x, y]
					return [metricValue.get('timestamp'), metricValue.get('value')]

			seriesNamesById = dataSeries.keySeq().map (metricId) =>
				return [metricId, @props.metricsById.get(metricId).get('name')]
			.fromEntrySeq().toMap()

			# Create set to show which x maps to which y
			xsMap = dataSeries.keySeq()
			.map (seriesId) ->
				return ['y-' + seriesId, 'x-' + seriesId]
			.fromEntrySeq().toMap()


			dataSeriesNames = dataSeries.keySeq()
			.map (seriesId) =>
				return ['y-' + seriesId, seriesNamesById.get(seriesId)]
			.fromEntrySeq().toMap()
			

			dataSeries = dataSeries.entrySeq().flatMap ([seriesId, dataPoints]) ->
				xValues = Imm.List(['x-' + seriesId]).concat(
					dataPoints.map ([x, y]) -> x
				)
				yValues = Imm.List(['y-' + seriesId]).concat(
					dataPoints.map ([x, y]) -> y
				)
				return Imm.List([xValues, yValues])

			scaledDataSeries = dataSeries.map (metric) ->
				# Filter out id's to figure out min & max
				values = metric.flatten().filterNot (y) -> isNaN(y)
				.map (val) -> return Number(val)

				# Figure out min and max metric values
				min = values.min()
				max = values.max()

				# Center the line vertically if constant value
				if min is max
					min -= 1
					max += 1

				scaleFactor = max - min			

				# Map scaleFactor on to numerical values
				return metric.map (dataPoint) ->
					return dataPoint if isNaN(dataPoint)
					(dataPoint - min) / scaleFactor
					

			# YEAR LINES
			# Build Imm.List of years and timestamps to matching
			newYearLines = Imm.List()
			firstYear = @props.xTicks.first().year()
			lastYear = @props.xTicks.last().year()

			# Don't bother if only 1 year (doesn't go past calendar year)
			unless firstYear is lastYear
				newYearLines = Imm.List([firstYear..lastYear]).map (year) =>
					return {
						value: Moment().year(year).startOf('year')
						text: year
						position: 'middle'
						class: 'yearLine'
					}			


			# Generate and bind the chart
			@_chart = C3.generate {						
					bindto: @refs.chartDiv.getDOMNode()
					grid: {
						x: {
							lines: newYearLines.toJS()
						}
					}
					axis: {
						x: {
							type: 'timeseries'
							tick: {
								fit: false
								format: '%b %d'
							}
							min: @props.xTicks.get @props.timeSpan[0]
							max: @props.xTicks.get @props.timeSpan[1]
						}
						y: {
							show: false
							max: 1
						}
					}				
					data: {
						hide: true
						xFormat: D3TimestampFormat
						columns: scaledDataSeries.toJS()
						xs: xsMap.toJS()
						names: dataSeriesNames.toJS()
					}
					tooltip: {
						format: {
							value: (value, ratio, id, index) ->
								# Filter out dataset from dataSeries with matching id, grab from index
								return dataSeries.filter((metric) ->
									return metric.contains id
								).flatten().get(index + 1)
							title: (timestamp) ->
								return Moment(timestamp).format('MMMM D [at] HH:mm')
						}
					}
					legend: {
						item: {
							onclick: (id) ->
								return false
						}
					}
					padding: {
						left: 25
						right: 25
					}
					onrendered: @_attachKeyBindings
				}

		_refreshSelectedMetrics: ->
			@_chart.hide()

			@props.selectedMetricIds.forEach (metricId) =>
				@_chart.show("y-" + metricId)	

		_refreshSelectedProgEvents: ->
			# Generate c3 regions array
			progEventRegions = @_generateProgEventRegions()

			console.log 'Regions going into c3:', progEventRegions.toJS()

			# Flush and re-apply regions to c3 chart
			@_chart.regions.remove()
			@_chart.regions.add progEventRegions.toJS()

			# Bind user interaction events
			@_attachKeyBindings progEventRegions

			@setState => {progEventRegions}

		_generateProgEventRegions: ->
			# Filter out progEvents that aren't selected
			selectedProgEvents = @props.progEvents.filter (progEvent) =>
				return @props.selectedProgEventIds.contains progEvent.get('id')

			# Build Imm.List of region objects
			progEventRegions = selectedProgEvents.map (progEvent) =>
				eventRegion = {
					start: @_toUnixMs progEvent.get('startTimestamp')
					class: "progEventRange #{progEvent.get('id')}"
				}
				if Moment(progEvent.get('endTimestamp'), TimestampFormat).isValid()
					eventRegion.end = @_toUnixMs progEvent.get('endTimestamp')

				# TODO: Classify singular event
				return eventRegion

			# Sort regions in order of start timestamp
			sortedEvents = progEventRegions.sortBy (event) => event['start']

			# Setting up vars for row sorting
			remainingEvents = sortedEvents
			eventRows = Imm.List()
			progEvents = Imm.List()
			rowIndex = 0

			# Process progEvents for regions while remaining events
			while remainingEvents.size > 0

				# Init new eventRow
				eventRows = eventRows.push Imm.List()

				# Loop through events, pluck any with non-conflicting dates
				remainingEvents.forEach (thisEvent) =>

					thisRow = eventRows.get(rowIndex)
					# Can't rely on forEach index, because .delete() offsets it
					liveIndex = remainingEvents.indexOf(thisEvent)

					# Let's pluck this progEvent if no rows or timestamps don't conflict
					if thisRow.size is 0 or (
						not thisRow.last().get('end')? or 
						thisEvent.start >= thisRow.last().get('end')
					)
						# Append class with row number
						progEvent = Imm.fromJS(thisEvent)
						newClass = progEvent.get('class') + " row#{rowIndex}"				

						# Convert single-point event date to a short span
						if not progEvent.get('end')
							startDate = Moment progEvent.get('start')
							progEvent = progEvent.set 'end', startDate.clone().add(6, 'hours')
							newClass = newClass + " singlePoint"

						# Update class
						progEvent = progEvent.set('class', newClass)

						# Update eventRows, remove from remainingEvents
						updatedRow = eventRows.get(rowIndex).push progEvent
						eventRows = eventRows.set rowIndex, updatedRow
						remainingEvents = remainingEvents.delete(liveIndex)


				# Cancat to final (flat) output for c3
				progEvents = progEvents.concat eventRows.get(rowIndex)

				rowIndex++


			# Determine regions height
			chartHeightY = 1 + (eventRows.size * 1/4)

			console.log 'chartHeightY', chartHeightY

			@_chart.axis.max {
				y: chartHeightY
			}

			return progEvents

		_attachKeyBindings: ->
			# Find our hidden eventInfo box
			eventInfo = $('#eventInfo')
			dateFormat = 'Do MMM [at] h:mm A'

			@props.progEvents.forEach (progEvent) =>
				# Attach hover binding to progEvent region
				$('.' + progEvent.get('id')).hover((event) =>					

					eventInfo.addClass('show')
					eventInfo.find('.title').text progEvent.get('title')
					eventInfo.find('.description').text(progEvent.get('description') or "(no description)")

					startTimestamp = new Moment(progEvent.get('startTimestamp'), TimestampFormat)
					endTimestamp = new Moment(progEvent.get('endTimestamp'), TimestampFormat)

					startText = startTimestamp.format(dateFormat)
					endText = if endTimestamp.isValid() then endTimestamp.format(dateFormat) else null

					if endText?
						startText = "From: " + startText
						endText = "Until: " + endText

					eventInfo.find('.start').text startText
					eventInfo.find('.end').text endText

					# Make eventInfo follow the mouse
					$(win.document).on('mousemove', (event) ->
						eventInfo.css 'top', event.clientY - (eventInfo.outerHeight() + 15)
						eventInfo.css 'left', event.clientX
					)
				, =>
					# Hide and unbind!
					eventInfo.removeClass('show')
					$(win.document).off('mousemove')
				)

		_toUnixMs: (timestamp) ->
			# Converts to unix ms
			return Moment(timestamp, TimestampFormat).valueOf()		



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
