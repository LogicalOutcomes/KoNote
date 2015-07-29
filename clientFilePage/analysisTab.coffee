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
					if @props.isVisible
						# Force chart to be recreated when tab is opened
						Chart({
							progNotes: @props.progNotes
							metricsById: @props.metricsById
							metricValues
							selectedMetricIds: @state.selectedMetricIds
						})
				)
			)

		componentDidMount: ->
			console.log "@state.selectedMetricIds", @state.selectedMetricIds.toJS()
			# Show anything that is selected in the view layer
			# TODO: Make this work. Plz?
			@state.selectedMetricIds.forEach (metricId) =>
				console.log "metricId", metricId
				Chart.chart.show("y" + metricId)

		_updateMetricSelection: (metricId) ->
			@setState ({selectedMetricIds}) ->
				if selectedMetricIds.contains metricId
					selectedMetricIds = selectedMetricIds.delete metricId
					Chart.chart.hide ("y-" + metricId)
				else
					selectedMetricIds = selectedMetricIds.add metricId
					Chart.chart.show ("y-" + metricId)

				return {selectedMetricIds}			

	Chart = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]
		render: ->
			return R.div({className: 'chart', ref: 'chartDiv'})
				
		componentDidMount: ->
			@_generateChart()

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




			timeStamps = Imm.List()
			# Grab all unique timestamps (timestamp format is 23ch long)
			dataSeries.forEach (metric) ->
				metric.forEach (dataPoint) ->
					if not timeStamps.contains(dataPoint) and dataPoint.length is 23
						timeStamps = timeStamps.push dataPoint

			timeMoments = timeStamps.map (stamp) ->
				return new Moment(stamp, Persist.TimestampFormat).startOf('day')
			
			# Figure out min and max timeMoments
			earliestTime = Moment.min(timeMoments.toJS())
			latestTime = Moment.max(timeMoments.toJS())

			# console.log "DIFF:", latestTime.diff(earliestTime, 'days')




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

			Chart.chart = C3.generate {
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
								if metric.contains id then return metric
							).flatten().get(index + 1)
					}						
				}
				legend: {
					item: {
						onclick: (id) ->
							return false
					}
				}
			}			

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
