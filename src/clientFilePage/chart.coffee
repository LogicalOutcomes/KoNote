# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Chart component that generates and interacts with C3 API from prop changes

Imm = require 'immutable'
Moment = require 'moment'

Config = require '../config'


load = (win) ->
	$ = win.jQuery
	C3 = win.c3
	React = win.React
	{PropTypes} = React
	R = React.DOM

	{TimestampFormat} = require('../persist/utils')
	D3TimestampFormat = '%Y%m%dT%H%M%S%L%Z'
	hiddenId = "-h-" # Fake/hidden datapoint's ID


	Chart = React.createFactory React.createClass
		displayName: 'Chart'
		mixins: [React.addons.PureRenderMixin]
		# TODO: propTypes

		getInitialState: -> {
			eventRows: 0
			hoveredMetric: null
		}

		# TODO: propTypes

		render: ->
			return R.div({
				className: 'chartInner'
				ref: 'chartInner'
			},
				R.div({
					className: "chart"
					ref: 'chartDiv'
				})
			)

		# TODO: Use componentWillReceiveProps here?
		componentDidUpdate: (oldProps, oldState) ->
			# Perform resize first so chart renders new data properly
			@_refreshChartHeight()

			# Update timeSpan?
			sameTimeSpan = Imm.is @props.timeSpan, oldProps.timeSpan
			unless sameTimeSpan
				newMin = @props.timeSpan.get('start')
				newMax = @props.timeSpan.get('end')

				# C3 requires there's some kind of span (even if it's 1ms)
				# todo check this
				if newMin is newMax
					newMax = newMax.clone().endOf 'day'

				@_chart.axis.min {x: newMin}
				@_chart.axis.max {x: newMax}

			# Update selected metrics?
			sameSelectedMetrics = Imm.is @props.selectedMetricIds, oldProps.selectedMetricIds
			unless sameSelectedMetrics
				@_refreshSelectedMetrics()

			# Destroy and re-mount chart when values changed
			# TODO: Make this more efficient
			sameMetricValues = Imm.is @props.metricValues, oldProps.metricValues
			if not sameMetricValues and @_chart?
				console.info "Re-drawing chart..."
				@_chart.destroy()
				@componentDidMount()

			# Update chart min/max range from changed xTicks?
			sameXTicks = Imm.is @props.xTicks, oldProps.xTicks
			unless sameXTicks
				@_chart.axis.range {
					min: {x: @props.xTicks.first()}
					max: {x: @props.xTicks.last()}
				}

			# Update chart type?
			sameChartType = Imm.is @props.chartType, oldProps.chartType
			unless sameChartType
				@_generateChart()
				@_refreshSelectedMetrics()


		componentDidMount: ->
			@_generateChart()
			@_refreshSelectedMetrics()
			@_refreshChartHeight(true)

		_generateChart: ->
			console.log "Generating Chart...."
			# Create a Map from metric ID to data series,
			# where each data series is a sequence of [x, y] pairs

			# Inject hidden datapoint, with value well outside y-span
			metricValues = @props.metricValues.push Imm.Map {
				id: hiddenId
				timestamp: Moment().format(TimestampFormat)
				value: -99999
			}

			dataSeries = metricValues
			.groupBy (metricValue) -> # group by metric
				return metricValue.get('id')
			.map (metricValues) -> # for each data series
				return metricValues.map (metricValue) -> # for each data point
					# [x, y]
					return [metricValue.get('timestamp'), metricValue.get('value')]

			seriesNamesById = dataSeries.keySeq().map (metricId) =>
				# Ignore hidden datapoint
				metricName = if metricId is hiddenId
					metricId
				else
					@props.metricsById.get(metricId).get('name')

				return [metricId, metricName]
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
				# Ensure ordered by earliest-latest
				orderedDataPoints = dataPoints
				.sortBy ([x, y]) -> x

				xValues = Imm.List(['x-' + seriesId]).concat(
					orderedDataPoints.map ([x, y]) -> x
				)
				yValues = Imm.List(['y-' + seriesId]).concat(
					orderedDataPoints.map ([x, y]) -> y
				)
				return Imm.List([xValues, yValues])

			scaledDataSeries = dataSeries.map (series) ->
				# Scaling only applies to y series
				return series if series.first()[0] isnt 'y'
				# Ignore hidden datapoint
				return series if series.first() is "y-#{hiddenId}"

				# Filter out id's to figure out min & max
				values = series.flatten()
				.filterNot (y) -> isNaN(y)
				.map (val) -> return Number(val)

				# Figure out min and max series values
				# Min is enforced as 0 for better visual proportions
				# unless lowest value is negative
				lowestValue = values.min()
				hasNegativeValue = lowestValue < 0

				min = if hasNegativeValue then lowestValue else 0
				max = values.max()

				# Center the line vertically if constant value
				if min is max
					min -= 1
					max += 1

				scaleFactor = max - min

				# Map scaleFactor on to numerical values
				return series.map (dataPoint) ->
					unless isNaN(dataPoint)
						(dataPoint - min) / scaleFactor
					else
						dataPoint

			# Min/Max x dates
			#minDate = @props.xTicks.first()
			#maxDate = @props.xTicks.last()
			minDate = @props.timeSpan.get('start')
			maxDate = @props.timeSpan.get('end')

			# YEAR LINES
			# Build Imm.List of years and timestamps to matching
			newYearLines = Imm.List()
			firstYear = minDate.year()
			lastYear = maxDate.year()

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
				bindto: @refs.chartDiv
				grid: {
					x: {
						lines: newYearLines.toJS()
					}
				}
				axis: {
					x: {
						#min: minDate
						#max: maxDate
						type: 'timeseries'
						tick: {
							fit: false
							format: '%b %d' if (maxDate.diff(minDate, 'days') > 3)
						}
					}
					y: {
						show: false
						max: 1
						min: 0
					}
				}
				regions: @props.weekends.toJS()
				data: {
					type: @props.chartType
					hide: true
					xFormat: D3TimestampFormat
					columns: scaledDataSeries.toJS()
					xs: xsMap.toJS()
					names: dataSeriesNames.toJS()
					classes: {
						hiddenId: 'hiddenId'
					}
					# Get/destroy hovered metric point data in local memory
					onmouseover: (d) => @hoveredMetric = d
					onmouseout: (d) => @hoveredMetric = null if @hoveredMetric? and @hoveredMetric.id is d.id
				}
				spline: {
					interpolation: {
						type: 'monotone'
					}
				}
				point: {
					r: 6
				}
				tooltip: {
					format: {
						value: (value, ratio, id, index) ->
							actualValue = dataSeries
							.find (series) -> series.contains id
							.get(index + 1)

							return actualValue

						title: (timestamp) ->
							return Moment(timestamp).format(Config.timestampFormat)
					}
					# Customization from original c3 tooltip DOM code: http://stackoverflow.com/a/25750639
					contents: (metrics, defaultTitleFormat, defaultValueFormat, color) =>
						# Lets us distinguish @_chart's local `this` (->) methods from Chart's `this` (=>)
						# http://stackoverflow.com/a/15422322
						$$ = ` this `

						config = $$.config
						titleFormat = config.tooltip_format_title or defaultTitleFormat
						nameFormat = config.tooltip_format_name or (name) -> name

						valueFormat = config.tooltip_format_value or defaultValueFormat
						text = undefined
						title = undefined
						value = undefined
						name = undefined
						bgcolor = undefined

						tableContents = metrics
						.sort (a, b) -> b.value - a.value # Sort by scaled value (desc)
						.forEach (currentMetric) =>
							# Is this metric is currently being hovered over?
							isHoveredMetric = @hoveredMetric? and (
								@hoveredMetric.id is currentMetric.id or # Is currently hovered (top layer)
								Math.abs(@hoveredMetric.value - currentMetric.value) < 0.025 # Is hiding behind hovered metric
							)

							# Ignore empty values? TODO: Check this
							if !(currentMetric and (currentMetric.value or currentMetric.value == 0))
								return

							if !text
								title = if titleFormat then titleFormat(currentMetric.x) else currentMetric.x
								text = '<table class=\'' + $$.CLASS.tooltip + '\'>' + (if title or title == 0 then '<tr><th colspan=\'2\'>' + title + '</th></tr>' else '')

							name = nameFormat(currentMetric.name)
							value = valueFormat(currentMetric.value, currentMetric.ratio, currentMetric.id, currentMetric.index)
							hoverClass = if isHoveredMetric then 'isHovered' else ''

							bgcolor = if $$.levelColor then $$.levelColor(currentMetric.value) else color(currentMetric.id)
							text += '<tr class=\'' + $$.CLASS.tooltipName + '-' + currentMetric.id + ' ' + hoverClass + '\'>'
							text += '<td class=\'name\'><span style=\'background-color:' + bgcolor + '\'></span>' + name + '</td>'
							text += '<td class=\'value\'>' + value + '</td>'
							text += '</tr>'

							# TODO: Show definitions for other metrics w/ overlapping regular or scaled values
							if isHoveredMetric
								metricId = currentMetric.id.substr(2) # Cut out "y-" for raw ID
								metricDefinition = @props.metricsById.getIn [metricId, 'definition']

								# Truncate definition to 100ch + ...
								if metricDefinition.length > 100
									metricDefinition = metricDefinition.substring(0, 100) + "..."

								text += '<tr class=\'' + $$.CLASS.tooltipName + '-' + currentMetric.id + ' + \'>'
								text += '<td class=\'definition\' colspan=\'2\'>' + metricDefinition + '</td>'
								text += '</tr>'

							return text

						text += '</table>'
						return text
				}
				item: {
					onclick: (id) -> return false
				}
				padding: {
					left: 25
					right: 25
				}
				size: {
					height: @_calculateChartHeight()
				}
				legend: {
					show: false
				}
				onresize: @_refreshChartHeight # Manually calculate chart height
			}

			# Fire metric colors up to analysisTab
			# TODO: Define these manually/explicitly, to avoid extra analysisTab render
			@props.updateMetricColors @_chart.data.colors()

		_calculateChartHeight: ->
			return $(@refs.chartInner).height() - 20

		_refreshChartHeight: (isForced = false) ->
			return unless @_chart?

			height = @_calculateChartHeight()

			# Skip c3 update if is current height
			if not isForced and height is $(@refs.chartDiv).height()
				return

			# Proceed with resizing the chart itself
			@_chart.resize {height}

		_refreshSelectedMetrics: ->
			console.log "Refreshing selected metrics..."
			@_chart.hide()
			@_chart.legend.hide()
			@_chart.show("y-#{hiddenId}")

			@props.selectedMetricIds.forEach (metricId) =>
				@_chart.show("y-" + metricId)
				@_chart.legend.show("y-" + metricId)

		_toUnixMs: (timestamp) ->
			# Converts to unix ms
			return Moment(timestamp, TimestampFormat).valueOf()


	return Chart

module.exports = {load}
