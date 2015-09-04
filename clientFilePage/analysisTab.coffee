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

	D3TimestampFormat = '%Y%m%dT%H%M%S%L%Z'
	TimeGranularities = ['Day', 'Week', 'Month', 'Year']

	AnalysisView = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]
		getInitialState: ->
			return {
				metricValues: null
				selectedMetricIds: Imm.Set()
				xTicks: Imm.List()
				xDays: Imm.List()
				timeSpan: [0, 1]
				timeGranulatiry: 'day'
			}
		componentWillMount: ->
			# All non-empty metric values
			metricValues = @props.progNotes.flatMap (progNote) ->
				return extractMetricsFromProgNote progNote
			.filter (metricValue) -> # remove blank metrics
				return metricValue.get('value').trim().length > 0

			# All metric IDs for which this client file has data
			metricIdsWithData = metricValues
			.map((m) -> m.get('id'))
			.toSet()


			# Builds list of ALL the timestamps
			timestamps = metricValues.map (metricValue) ->
				return Moment metricValue.get('timestamp'), Persist.TimestampFormat

			# Builds ordered set of unique timestamps (each as unix ms)
			middayTimeStamps = timestamps.map (timestamp) ->
				return timestamp.startOf('day').valueOf()
			.toOrderedSet().sort()

			# Figure out number of days with data
			daysOfData = middayTimeStamps.size

			# Disable chart view if less than 3 days of data
			if daysOfData < 3
				@setState => isDisabled: {message: "Sorry, 
				#{3 - daysOfData} more days of #{Term 'progress notes'} are required
				before I can chart anything meaningful here."}

			firstDay = Moment middayTimeStamps.first()
			lastDay = Moment middayTimeStamps.last()

			dayRange = lastDay.diff(firstDay, 'days') + 1

			# Return a list of full range of timestamps starting from 
			xTicks = Imm.List([0..dayRange]).map (n) ->
				firstDay.clone().add(n, 'days')

			@setState => {xDays: xTicks, xTicks, metricIdsWithData, metricValues}

		render: ->			
			# Is there actually enough information to show something?
			hasData = @state.metricIdsWithData.size > 0

			return R.div({className: "view analysisView #{showWhen @props.isVisible}"},
				R.div({className: "noData #{showWhen not hasData}"},
					R.div({},
						R.h1({}, "No data to #{Term 'analyze'}")
						R.div({},
							"This tab will become available when this #{Term 'client'} has
							one or more #{Term 'progress notes'} that contain #{Term 'metrics'}."
						)
					)
				)
				R.div({className: "timeScaleToolbar #{showWhen hasData}"},
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
								date = Moment(@state.xTicks.get(index)).format('dddd - Do MMMM - YYYY')
								return R.div({},
									R.span({}, date)
								)
							)
						)
					)
					R.div({className: 'granularContainer'},
						# Slider({
						# 	ref: 'granularSlider'
						# 	isEnabled: true
						# 	defaultValue: 0
						# 	ticks: TimeGranularities
						# 	tickRegions: true
						# 	onChange: @_updateGranularity
						# })
					)
				)
				R.div({className: "mainWrapper #{showWhen hasData}"},
					R.div({className: "chartContainer"},
						if @props.isVisible
							# Force chart to be recreated when tab is opened
							Chart({
								ref: 'mainChart'
								progNotes: @props.progNotes
								progEvents: @props.progEvents
								metricsById: @props.metricsById
								metricValues: @state.metricValues
								xTicks: @state.xTicks
								selectedMetricIds: @state.selectedMetricIds								
								timeSpan: @state.timeSpan
							})
					)
					R.div({className: "selectionPanel #{showWhen hasData}"},
						R.div({className: 'heading'}, Term 'Metrics')
						R.div({className: 'metrics'},
							(@state.metricIdsWithData.map (metricId) =>
								metric = @props.metricsById.get(metricId)

								R.div({className: 'metric checkbox'},
									R.label({},
										R.input({
											type: 'checkbox'
											onChange: @_updateSelectedMetrics.bind null, metricId
											checked: @state.selectedMetricIds.contains metricId
										})
										metric.get('name')
									)
								)
							).toJS()...
						)
					)
				)				
			)

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

		# _updateGranularity: (event) ->
		# 	timeGranularity = event.target.value
		# 	@setState {timeGranularity}

		# 	console.log "xTicks:", @state.xTicks.toJS()

		# 	tickDays = @state.xTicks

		# 	startFirstWeek = tickDays.first().startOf('week')
		# 	endLastWeek = tickDays.last().endOf('week')

		# 	numberWeeks = endLastWeek.diff startFirstWeek, 'weeks'

		# 	console.log "numberWeeks", numberWeeks

		# 	tickWeeks = Imm.List([0...numberWeeks]).map (weekIndex) =>
		# 		return startFirstWeek.clone().add(weekIndex, 'weeks')

		# 	console.log "tickWeeks", tickWeeks.toJS()

		# 	@setState {xTicks: tickWeeks}


	Slider = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			slider: null

		componentDidMount: ->
			@setState {
				slider: $(@refs.slider.getDOMNode()).slider({
					enabled: @props.isEnabled
					tooltip: if @props.tooltip then 'show' else 'hide'
					range: @props.isRange or false
					min: @props.minValue or 0
					max: @props.maxValue or @props.ticks.length
					ticks: [0...TimeGranularities.length] if @props.tickRegions
					ticks_labels: TimeGranularities if @props.tickRegions
					value: @props.defaultValue
					formatter: @props.formatter or ((value) -> value)
				})
			}, =>
				@state.slider.on('slideStop', (event) => @props.onChange event)

		render: ->
			return R.input({ref: 'slider'})

		# componentDidUpdate: (oldProps, oldState) ->
		# 	console.log "Enabled?", @props.isEnabled
		# 	if @state.slider? and @props.isEnabled isnt oldProps.isEnabled				
		# 		if @props.isEnabled
		# 			console.log "Enabling..."
		# 			@state.slider.enable()
		# 		else
		# 			console.log "Disabling..."
		# 			@state.slider.disable()


	Chart = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]
		getInitialState: ->
			return {
				isDisabled: null
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
					className: "chart disabledChart #{showWhen !!@state.isDisabled}"
				}, 
					R.span({}, if @state.isDisabled then @state.isDisabled.message)
				)
				R.div({
					className: "chart #{showWhen not @state.isDisabled}"
					ref: 'chartDiv'
				})
			)

		componentDidUpdate: (oldProps, oldState) ->
			# Show anything that is selected in the view layer
			if @state.isDisabled
				return

			# Update metrics?
			sameMetrics = Imm.is @props.selectedMetricIds, oldProps.selectedMetricIds
			unless sameMetrics
				@_refreshSelectedMetrics()

			# Update timeSpan?
			sameTimeSpan = @props.timeSpan is oldProps.timeSpan
			unless sameTimeSpan
				@_chart.axis.min {x: @props.xTicks.get(@props.timeSpan[0])}
				@_chart.axis.max {x: @props.xTicks.get(@props.timeSpan[1])}	
				
		componentDidMount: ->			
			@_generateChart()
			@_refreshSelectedMetrics()
			@_attachKeyBindings()

		_refreshSelectedMetrics: ->
			@_chart.hide()

			@props.selectedMetricIds.forEach (metricId) =>
				@_chart.show("y-" + metricId)

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

		_generateChart: ->			
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
			# Build Imm.List of years and timestamps to match
			# TODO: This could be refined into a single mapped collection
			newYears = Imm.List()
			newYearLines = Imm.List()			

			@props.xTicks.forEach (tick) =>
				unless newYears.contains tick.year()
					newYears = newYears.push tick.year()
					newYearLines = newYearLines.push {
						value: if tick.isSame @props.xTicks.first() then tick else tick.startOf('year')
						text: tick.year()
						position: 'middle'
						class: 'yearLine'
					}

			# PROG EVENT REGIONS
			# Build Imm.List of region objects
			progEventRegions = @props.progEvents.map (progEvent) =>
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

			_pluckProgEvent = (thisEvent, index) ->
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
				remainingEvents = remainingEvents.delete(index)				

				return

			while remainingEvents.size > 0
				# Init new eventRow
				eventRows = eventRows.push Imm.List()

				# Loop through events, pluck any with non-conflicting dates
				remainingEvents.forEach (thisEvent) =>

					thisRow = eventRows.get(rowIndex)
					# Can't rely on forEach index, because .delete() offsets it
					liveIndex = remainingEvents.indexOf(thisEvent)

					_pluckProgEvent(thisEvent, liveIndex) if thisRow.size is 0 or (
						not thisRow.last().get('end')? or 
						thisEvent.start >= thisRow.last().get('end')
					)

				# Cancat to final (flat) output for c3
				progEvents = progEvents.concat eventRows.get(rowIndex)

				rowIndex++


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
							min: @props.xTicks.first().clone().format Persist.TimestampFormat
							max: @props.xTicks.last().clone().format Persist.TimestampFormat
						}
						y: {
							show: false
							max: 1 + (eventRows.size * 1/4)
						}
					}				
					data: {
						hide: true
						xFormat: D3TimestampFormat
						columns: scaledDataSeries.toJS()
						xs: xsMap.toJS()
						names: dataSeriesNames.toJS()
					}
					regions: progEvents.toJS()
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

		_toUnixMs: (timestamp) ->
			# Converts to unix ms
			return Moment(timestamp, TimestampFormat).valueOf()		



	extractMetricsFromProgNote = (progNote) ->
		switch progNote.get('type')
			when 'basic'
				# Quick notes don't have metrics
				return Imm.List()
			when 'full'
				return progNote.get('sections').flatMap (section) ->
					return extractMetricsFromProgNoteSection section, progNote.get('timestamp')
			else
				throw new Error "unknown prognote type: #{JSON.stringify progNote.get('type')}"

	extractMetricsFromProgNoteSection = (section, timestamp) ->
		switch section.get('type')
			when 'basic'
				return section.get('metrics').map (metric) ->
					return Imm.Map({
						id: metric.get('id')
						timestamp
						value: metric.get('value')
					})
			when 'plan'
				return section.get('targets').flatMap (target) ->
					return target.get('metrics').map (metric) ->
						return Imm.Map({
							id: metric.get('id')
							timestamp
							value: metric.get('value')
						})
			else
				throw new Error "unknown prognote section type: #{JSON.stringify section.get('type')}"


	return {AnalysisView}




module.exports = {load}
