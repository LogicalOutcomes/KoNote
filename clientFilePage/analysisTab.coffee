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

			# Create a Map from metric ID to data series,
			# where each data series is a sequence of [x, y] pairs
			dataSeries = metricValues
			.filter (metricValue) => # keep only data for selected metrics
				return @state.selectedMetricIds.contains metricValue.get('id')
			.groupBy (metricValue) -> # group by metric
				return metricValue.get('id')
			.map (metricValues) -> # for each data series
				return metricValues.map (metricValue) -> # for each data point
					# [x, y]
					return [metricValue.get('timestamp'), metricValue.get('value')]

			seriesNamesById = dataSeries.keySeq().map (metricId) =>
				return [metricId, @props.metricsById.get(metricId).get('name')]
			.fromEntrySeq().toMap()

			# Is there actually enough information to show something?
			hasData = metricIdsWithData.size > 0

			return R.div({className: "view analysisView #{showWhen @props.isVisible}"},
				R.div({className: "noData #{showWhen not hasData}"},
					R.h1({}, "Not enough data.")
					R.div({},
						"This tab will become available when this #{Term 'client'} has
						one or more #{Term 'progress notes'} that contain #{Term 'metrics'}."
					)
				)
				R.div({className: "controlPanel #{showWhen hasData}"},
					R.div({className: 'heading'}, Term 'Metrics')
					R.div({className: 'metrics'},
						(metricIdsWithData.map (metricId) =>
							metric = @props.metricsById.get(metricId)

							R.div({className: 'metric checkbox'},
								R.label({},
									R.input({
										type: 'checkbox'
										onChange: @_updateMetricSelection.bind null, metricId
										checked: @state.selectedMetricIds.contains metricId
									})
									metric.get('name')
								)
							)
						).toJS()...
					)
				)
				R.div({className: "chartContainer #{showWhen hasData}"},
					(if @props.isVisible
						# Force chart to be recreated when tab is opened
						(if dataSeries.size > 0
							Chart({data: dataSeries, seriesNamesById})
						else
							R.div({className: 'noData'},
								"Select items above to see them graphed here."
							)
						)
					)
				)
			)
		_updateMetricSelection: (metricId) ->
			@setState ({selectedMetricIds}) ->
				if selectedMetricIds.contains metricId
					selectedMetricIds = selectedMetricIds.delete metricId
				else
					selectedMetricIds = selectedMetricIds.add metricId

				return {selectedMetricIds}

	Chart = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]
		render: ->
			return R.div({className: 'chart', ref: 'chartDiv'})
		componentDidMount: ->
			@_chart = C3.generate {
				bindto: @refs.chartDiv.getDOMNode()
				axis: {
					x: {
						type: 'timeseries'
						tick: {
							fit: false
							format: '%Y-%m-%d'
						}
					}
					y: {
						show: false
					}
				}
				data: {
					xFormat: D3TimestampFormat
					columns: []
				}
			}
			@_refreshData()
		componentDidUpdate: ->
			@_refreshData()
		_refreshData: ->
			xsMap = @props.data.keySeq()
			.map (seriesId) ->
				return ['y-' + seriesId, 'x-' + seriesId]
			.fromEntrySeq().toMap()

			dataSeriesNames = @props.data.keySeq()
			.map (seriesId) =>
				return ['y-' + seriesId, @props.seriesNamesById.get(seriesId)]
			.fromEntrySeq().toMap()

			dataSeries = @props.data.entrySeq().flatMap ([seriesId, dataPoints]) ->
				xValues = Imm.List(['x-' + seriesId]).concat(
					dataPoints.map ([x, y]) -> x
				)
				yValues = Imm.List(['y-' + seriesId]).concat(
					dataPoints.map ([x, y]) -> y
				)
				return Imm.List([xValues, yValues])

			ticks = dataSeries.forEach (metric) ->
				console.log metric.toJS()
				return metric

			scaledDataSeries = dataSeries.map (metric) ->
				# Filter out id's to figure out min & max
				values = metric.flatten().filterNot (y) -> isNaN(y)
				.map((val) -> return Number(val))

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


			originalGetTooltipContent = @_chart.internal.getTooltipContent

			# Hijack the tooltip, while getting called, to use original dataSeries value
			@_chart.internal.getTooltipContent = (data, defaultTitleFormat, defaultValueFormat, color) ->
				originalValues = data.map (dataPoint, i) ->
					if dataPoint
						# Pick the array from original data with matching ID
						thisPointArray = dataSeries.filter((metric) -> if metric.contains dataPoint.id then return metric).flatten()
						return {
							id: dataPoint.id
							index: dataPoint.index
							name: dataPoint.name
							value: thisPointArray.get(dataPoint.index + 1)
							x: dataPoint.x
						}
					else
						return dataPoint
				# Call the hijacked tooltip display function
				return originalGetTooltipContent.call(this, originalValues, defaultTitleFormat, defaultValueFormat, color)

			@_chart.load {
				xs: xsMap.toJS()
				columns: scaledDataSeries.toJS()
				unload: true
			}
			@_chart.data.names dataSeriesNames.toJS()

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
