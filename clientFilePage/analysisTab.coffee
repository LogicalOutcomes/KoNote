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

	AnalysisView = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]
		getInitialState: ->
			return {
				selectedMetricIds: Imm.Set()
			}
		render: ->
			# All non-empty metric values
			metricValues = @props.progNotes.flatMap (progNote) ->
				return extractMetricsFromProgNote progNote
			.filter (metricValue) -> # remove blank metrics
				return metricValue.get('value').trim().length > 0

			# All metric IDs for which this client file has data
			metricIdsWithData = metricValues
			.map((m) -> m.get('id'))
			.toSet()

			# Is there actually enough information to show something?
			hasData = metricIdsWithData.size > 0

			return R.div({className: "view analysisView #{showWhen @props.isVisible}"},
				R.div({className: "noData #{showWhen not hasData}"},
					R.h1({}, "No data to #{Term 'analyze'}")
					R.div({},
						"This tab will become available when this #{Term 'client'} has
						one or more #{Term 'progress notes'} that contain #{Term 'metrics'}."
					)
				)
				R.div({className: "timeScaleToolbar #{showWhen hasData}"},
					R.div({id: 'timeSpanContainer'},
						RangeSlider({
							ref: 'timeSpanSlider'
							isRange: true
							defaultValue: [1,7]
							minValue: 0
							maxValue: 10
						})
					)
					R.div({id: 'granularContainer'},
						RangeSlider({
							ref: 'granularSlider'
							defaultValue: 0
							minValue: 0
							maxValue: 10
						})
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
								metricValues
								selectedMetricIds: @state.selectedMetricIds
							})
					)
					R.div({className: "selectionPanel #{showWhen hasData}"},
						R.div({className: 'heading'}, Term 'Metrics')
						R.div({className: 'metrics'},
							(metricIdsWithData.map (metricId) =>
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


	RangeSlider = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]
		getInitialState: ->
			return {
				minDate: null
				maxDate: null
			}

		componentDidMount: ->
			$(@refs.slider.getDOMNode()).slider({
				range: @props.isRange
				tooltip: 'always'

				value: @props.defaultValue
				min: @props.minValue
				max: @props.maxValue
			})

		render: ->			
			return R.input({ref: 'slider'})


	Chart = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]
		getInitialState: ->
			return {
				isDisabled: null
			}

		render: ->
			return R.div({className: 'chartInner'},
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
			sameProps = Imm.is @props.selectedMetricIds, oldProps.selectedMetricIds
			unless sameProps or !!@state.isDisabled
				@_refreshSelectedMetrics()
				
		componentDidMount: ->			
			@_generateChart()
			@_refreshSelectedMetrics()
			@_attachKeyBindings()

		_refreshSelectedMetrics: ->
			# $('.c3-regions').insertBefore('.c3-chart')

			@_chart.hide()

			@props.selectedMetricIds.forEach (metricId) =>
				@_chart.show("y-" + metricId)

		_attachKeyBindings: ->
			region = $('.c3-regions').clone()
			region.insertAfter('.c3-chart')

			# Copy regions group to top layer (above main chart)
			# Simply moving group screws up c3
			# regions = $('.c3-regions').clone()
			# $('.c3-regions').empty()
			# regions.insertAfter('.c3-chart')

			# regions = $('.c3-regions').parseXML()

			# console.log "Regions", regions

			# $('.c3-regions').insertAfter('.c3-chart')

			# $('slider').click(=>)

			# @props.progEvents.forEach (progEvent) =>
				# console.log "Binding click to #{progEvent.get('id')}"
				# console.log $(".#{progEvent.get('id')} rect")[0]

				# $(".#{progEvent.get('id')} rect")[0].click ->
				# 	console.log "Clicked!"

				# $('.' + progEvent.get('id')).click(=> console.log "You clicked the event!")

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

			xTicks = @_generateXTicks()

			# YEAR LINES
			# Build Imm.List of years and timestamps to match
			# TODO: This could be refined into a single mapped collection
			newYears = Imm.List()
			newYearLines = Imm.List()			

			xTicks.forEach (tick) ->
				unless newYears.contains tick.year()
					newYears = newYears.push tick.year()
					newYearLines = newYearLines.push {
						value: if tick.isSame xTicks.first() then tick else tick.startOf('year')
						text: tick.year()
						position: 'middle'
						class: 'yearLine'
					}

			# PROG EVENT REGIONS
			# Build Imm.List of region objects
			progEventRegions = @props.progEvents.map (progEvent) =>
				eventRegion = {
					start: @_convertTimestamp progEvent.get('startTimestamp')
					class: "progEventRange #{progEvent.get('id')}"
				}
				if Moment(progEvent.get('endTimestamp'), TimestampFormat).isValid()
					eventRegion.end = @_convertTimestamp progEvent.get('endTimestamp')				

				return eventRegion

			console.log "ProgEvent Regions", progEventRegions.toJS()


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
							min: xTicks.first().clone().format Persist.TimestampFormat
							max: xTicks.last().clone().format Persist.TimestampFormat
						}
						y: {
							show: false
							max: 1.5
						}
					}				
					data: {
						hide: true
						xFormat: D3TimestampFormat
						columns: scaledDataSeries.toJS()
						xs: xsMap.toJS()
						names: dataSeriesNames.toJS()
					}
					regions: progEventRegions.toJS()
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
						left: 50
						right: 50
					}
					zoom: {
						# enabled: true
					}
				}

		_convertTimestamp: (timestamp) ->
			# Converts to unix ms
			return Moment(timestamp, TimestampFormat).valueOf()

		_generateXTicks: ->
			# Builds list of ALL the timestamps
			timestamps = @props.metricValues.map (metricValue) ->
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
			return Imm.List([0..dayRange]).map (n) ->
				firstDay.clone().add(n, 'days')



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
