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
	minChartHeight = 400
	palette = ['#66c088', '#43c5f1', '#5f707e', '#f06362', '#e5be31', '#9560ab', '#e883c0', '#ef8f39', '#42a795', '#999999', '#ccc5a8', '5569d8']


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
				ChartEventsStyling({
					ref: (comp) => @chartEventsStyling = comp
					selectedMetricIds: @props.selectedMetricIds
					progEvents: @props.progEvents
					eventRows: @state.eventRows
				})

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

				# avoid repeating x axis labels bug
				if (newMax.diff(newMin, 'days') > 3)
					@_chart.internal.config.axis_x_tick_format = '%b %d'
				else
					@_chart.internal.config.axis_x_tick_format = null

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

			# Update selected progEvents?
			sameProgEvents = Imm.is @props.progEvents, oldProps.progEvents
			unless sameProgEvents
				@_refreshProgEvents()

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
				@_refreshProgEvents()


		componentDidMount: ->
			@_generateChart()
			@_refreshSelectedMetrics()
			@_refreshProgEvents()
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
				return [seriesId, '?x-' + seriesId]
			.fromEntrySeq().toMap()


			dataSeriesNames = dataSeries.keySeq()
			.map (seriesId) =>
				return [seriesId, seriesNamesById.get(seriesId)]
			.fromEntrySeq().toMap()


			dataSeries = dataSeries.entrySeq().flatMap ([seriesId, dataPoints]) ->
				# Ensure ordered by earliest-latest
				orderedDataPoints = dataPoints
				.sortBy ([x, y]) -> x

				xValues = Imm.List(['?x-' + seriesId]).concat(
					orderedDataPoints.map ([x, y]) -> x
				)
				yValues = Imm.List([seriesId]).concat(
					orderedDataPoints.map ([x, y]) -> y
				)
				return Imm.List([xValues, yValues])

			scaledDataSeries = dataSeries.map (series) ->
				# Scaling only applies to y series
				return series if series.first()[0] is '?'
				# Ignore hidden datapoint
				return series if series.first() is hiddenId

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
						min: minDate
						max: maxDate
						type: 'timeseries'
						tick: {
							fit: false
							format: '%b %d'
						}
					}
					y: {
						show: false
						max: 1
						min: 0
					}
				}
				transition: {
					duration: 0
				}
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
					r: 5
				}
				tooltip: {
					format: {
						value: (value, ratio, id, index) ->
							actualValue = dataSeries
							.find (series) -> series.contains id
							.get(index + 1)

							return actualValue

						title: (timestamp) ->
							return Moment(timestamp).format(Config.longTimestampFormat)
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
								metricDefinition = @props.metricsById.getIn [currentMetric.id, 'definition']

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

		_calculateChartHeight: ->
			fullHeight = $(@refs.chartInner).height() - 20

			# Half-height for only metrics/events
			if @props.selectedMetricIds.isEmpty() or @props.progEvents.isEmpty()
				# Can return minimum height instead
				halfHeight = fullHeight / 2
				if halfHeight > minChartHeight
					return Math.floor halfHeight
				else
					return minChartHeight

			return fullHeight

		_refreshChartHeight: (isForced = false) ->
			return unless @_chart?

			height = @_calculateChartHeight()

			# Skip c3 update if is current height
			if not isForced and height is $(@refs.chartDiv).height()
				return

			# Update event regions' v-positioning if necessary
			if not @props.progEvents.isEmpty() and @chartEventsStyling?
				@chartEventsStyling.updateChartHeight(height)

			# Proceed with resizing the chart itself
			@_chart.resize {height}

		_refreshSelectedMetrics: ->
			@_chart.hide(null, {withLegend: true})
			unless @props.selectedMetricIds.size > 0
				# for events to work
				@_chart.show(hiddenId)
				return

			@props.selectedMetricIds.forEach (metricId) =>
				# choose metric color from palette
				# todo: move to analysis tab to save a render?
				if palette.includes(@_chart.data.colors()[metricId])
					# do not change the color if already set for this metric
					return
				else
					# assign a color from the palette that is not already in use
					for index, color of palette
						if Object.values(@_chart.data.colors()).includes color
						else
							@_chart.data.colors({"#{metricId}": palette[index]})
							return

			@_chart.show(@props.selectedMetricIds.toJS(), {withLegend: true})

			# fire metric colors back up to analysis tab
			@props.updateMetricColors Imm.Map(@_chart.data.colors())

		_refreshProgEvents: ->
			console.log "Refreshing progEvents..."
			# Generate c3 regions array
			progEventRegions = @_generateProgEventRegions()

			# Flush and re-apply regions to c3 chart
			@_chart.regions.remove()

			# C3 Regions have some kind of animation attached, which
			# messes up remove/add
			setTimeout(=>
				@_chart.regions progEventRegions.toJS()
				@_attachKeyBindings()
			, 500)

		_generateProgEventRegions: ->
			# Build Imm.List of region objects
			progEventRegions = @props.progEvents
			.map (progEvent) =>
				eventRegion = {
					start: @_toUnixMs progEvent.get('startTimestamp')
					class: "progEventRange #{progEvent.get('id')} typeId-"
				}

				eventRegion['class'] += if progEvent.get('typeId')
					progEvent.get('typeId')
				else
					"null" # typeId-null is how we know it doesn't have an eventType

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

				# Loop through events, pluck any for the given row with non-conflicting dates
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
						newClass = "#{progEvent.get('class')} row#{rowIndex}"

						# Convert single-point event date to a short span
						if not progEvent.get('end')
							startDate = Moment progEvent.get('start')
							progEvent = progEvent.set 'end', startDate.clone().add(6, 'hours')
							newClass = newClass + " singlePoint"

						# Update class (needs to be 'class' for C3js)
						progEvent = progEvent.set('class', newClass)

						# Update eventRows, remove from remainingEvents
						updatedRow = eventRows.get(rowIndex).push progEvent
						eventRows = eventRows.set rowIndex, updatedRow
						remainingEvents = remainingEvents.delete(liveIndex)


				# Concat to final (flat) output for c3
				progEvents = progEvents.concat eventRows.get(rowIndex)

				rowIndex++


			# Determine regions height
			chartHeightY = if eventRows.isEmpty() then 1 else 2

			# Metrics can be bigger when only 1 progEvent row
			if eventRows.size is 1
				chartHeightY = 1.5

			@setState {eventRows: eventRows.size}

			@_chart.axis.max {
				y: chartHeightY
			}

			return progEvents

		_attachKeyBindings: ->
			# TODO: Make sure listeners are removed when componentWillUnmount

			# Find our hidden eventInfo box
			eventInfo = $('#eventInfo')
			dateFormat = 'Do MMM [at] h:mm A'

			@props.progEvents.forEach (progEvent) =>
				# Attach hover binding to progEvent region
				$('.' + progEvent.get('id')).hover((event) =>

					description = progEvent.get('description') or "(no description)"
					if description.length > 1000
						description = description.substring(0, 2000) + " . . ."

					title = progEvent.get('title')

					# Tack on eventType to title
					# TODO: Do this earlier on, to save redundancy
					if progEvent.get('typeId')
						eventType = @props.eventTypes.find (eventType) -> eventType.get('id') is progEvent.get('typeId')
						eventTypeName = eventType.get('name')
						title = if title then "#{title} (#{eventTypeName})" else eventTypeName


					eventInfo.addClass('show')
					eventInfo.find('.title').text title
					eventInfo.find('.description').text(description)

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
						eventInfo.css 'top', event.clientY + 25
						eventInfo.css 'left', event.clientX
					)
				, =>
					# Hide and unbind!
					eventInfo.removeClass('show')
					$(win.document).off('mousemove')
				)


				rect = $('.' + progEvent.get('id')).find('rect')[0]

				# Fill progEvent region with eventType color if exists
				if progEvent.get('typeId') and not @props.eventTypes.isEmpty()
					eventType = @props.eventTypes
					.find (type) -> type.get('id') is progEvent.get('typeId')

					$(rect).attr({
						style:
							"fill: #{eventType.get('colorKeyHex')} !important;
							stroke: #{eventType.get('colorKeyHex')} !important;"
					})
				else
					# At least clear it for non-typed events
					$(rect).attr({style: ''})

		_toUnixMs: (timestamp) ->
			# Converts to unix ms
			return Moment(timestamp, TimestampFormat).valueOf()


	ChartEventsStyling = React.createFactory React.createClass
		displayName: 'ChartEventsStyling'

		propTypes: {
			eventRows: PropTypes.number.isRequired
			progEvents: PropTypes.instanceOf(Imm.List).isRequired
			selectedMetricIds: PropTypes.instanceOf(Imm.Set).isRequired
		}

		getInitialState: -> {
			chartHeight: null
		}

		updateChartHeight: (chartHeight) ->
			# This gets called alongside @_chart.resize
			@setState {chartHeight}

		render: ->
			# Calculate scaled height of each region (larger if no metrics)
			scaleFactor = if @props.selectedMetricIds.isEmpty() then 0.65 else 0.3
			scaleY = (scaleFactor / @props.eventRows).toFixed(2)


			R.style({},
				(Imm.List([0..@props.eventRows]).map (rowNumber) =>
					translateY = rowNumber * @state.chartHeight

					return ".chart .c3-regions .c3-region.row#{rowNumber} > rect {
						transform: scaleY(#{scaleY}) translateY(#{translateY}px) !important
					}"
				)
			)


	return Chart

module.exports = {load}
