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

		getInitialState: ->
			return {
				daysOfData: null
				selectedMetricIds: Imm.Set()
				chartType: 'spline'
				selectedEventTypeIds: Imm.Set()
				starredEventTypeIds: Imm.Set()
				excludedTargetIds: Imm.Set()
				timeSpan: null
				showSelection: true
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

			# Build list of timestamps from progEvents (start & end) & metrics
			daysOfData = Imm.List()
			.concat metricValues.map (metric) ->
				# Account for backdate, else normal timestamp
				metricTimestamp = metric.get('backdate') or metric.get('timestamp')
				return metricTimestamp
			.toOrderedSet()
			.sort()


			#################### Date Range / TimeSpan ####################

			# Determine earliest & latest days
			firstDay = Moment daysOfData.first(), TimestampFormat
			lastDay = Moment daysOfData.last(), TimestampFormat
			dayRange = lastDay.diff(firstDay, 'days') + 1

			# Create list of all days as moments
			xTicks = Imm.List([0..dayRange]).map (n) ->
				firstDay.clone().add(n, 'days')

			# weekend regions
			weekends = xTicks.filter (d) ->
				d.isoWeekday() is 6
			.map (d) -> {start: d.startOf('day'), end: d.clone().add(1, 'days').endOf('day')}

			# Declare default timeSpan
			# confirm we have enough data and set to 1 month
			if xTicks.size > 0 and xTicks.last().clone().subtract(1, "month").isSameOrAfter(xTicks.first())
				@defaultTimeSpan = Imm.Map {
					start: xTicks.last().clone().subtract(1, "month")
					end: xTicks.last()
				}
			else
				@defaultTimeSpan = Imm.Map {
					start: xTicks.first()
					end: xTicks.last()
				}

			# Assign default timespan if null
			timeSpan = if not @state.timeSpan? then @defaultTimeSpan else @state.timeSpan

			# Map out visible metric values (within timeSpan) by metric [definition] id
			visibleMetricValues = metricValues.filter (value) ->
				Moment(value.get('timestamp'), TimestampFormat).isBetween(timeSpan.get('start'), timeSpan.get('end'), null, '[]') # Inclusive

			visibleMetricValuesById = visibleMetricValues.groupBy (value) -> value.get('id')


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
							)

							R.div({className: 'chartContainer'},

								# Force chart to be re-rendered when tab is opened
								(unless @state.selectedEventTypeIds.isEmpty() and @state.selectedMetricIds.isEmpty()
									Chart({
										ref: 'mainChart'
										progNotes: @props.progNotes
										metricsById: @props.metricsById
										metricValues
										xTicks
										weekends
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
									R.div({className: "#{showWhen not @state.selectedMetricIds.isEmpty()}"},
										R.label({},
											"Line "
											R.input({
												type: 'checkbox'
												checked: @state.chartType is 'spline'
												onChange: @_updateChartType.bind null, 'spline'
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

						R.div({
							className: [
								'selectionPanel'
								'collapsed' unless @state.showSelection
							].join ' '
						},

							R.div({className: 'dataType panelHeader'},
								R.h2({
									className: 'selectionToggle'
									onClick: @_toggleSelectionPane
								},
									R.button({},
										(if @state.showSelection
											FaIcon('angle-right')
										else
											FaIcon('angle-left')
										)
									)
								)
							)

							R.div({
								className: [
									'dataType'
									'metrics'
									'collapsed' unless @state.showSelection
								].join ' '
							},
								allMetricsSelected = Imm.is @state.selectedMetricIds, metricIdsWithData

								(if planSectionsWithData.isEmpty()
									R.h2({className: 'noMetricPoints'},
										"(No #{Term 'metrics'} recorded)"
									)
								else
									R.h2({onClick: @_toggleAllMetrics.bind null, allMetricsSelected, metricIdsWithData},
										Term 'Metrics'
										R.span({className: 'helper'}
											R.input({
												type: 'checkbox'
												checked: allMetricsSelected
											})
											" Select All"
										)
									)
								)

								(unless planSectionsWithData.isEmpty()
									R.div({className: 'dataOptions'},
										(planSectionsWithData.map (section) =>
											PlanSectionMetricsSelection({
												key: section.get('id')
												sectionMetricsData: section
												visibleMetricValuesById
												selectedMetricIds: @state.selectedMetricIds
												metricColors: @state.metricColors
												updateSelectedMetrics: @_updateSelectedMetrics
											})
										)
									)
								)
								(unless unassignedMetricsList.isEmpty()
									UnassignedMetricsSelection({
										unassignedMetricsList
										visibleMetricValuesById
										selectedMetricIds: @state.selectedMetricIds
										metricColors: @state.metricColors
										updateSelectedMetrics: @_updateSelectedMetrics
									})
								)
							)
						)
					)
				)
			)

		_toggleSelectionPane: ->
			showSelection = not @state.showSelection
			@setState {showSelection}, =>
				setTimeout(=>
					if @refs.mainChart
						@refs.mainChart._refreshChartHeight(true)
				, 250)
			@setState {showSelection}

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


	# TODO EventTypesSelection, UntypedEventsSelection,
	# PlanSectionMetricsSelection, and UnassignedMetricsSelection are very
	# similar stylistically and functionally and could probably be refactored
	# into a generic "CollapsableSection" component.
	#
	# PlanTargetMetricsSelection is collapsable too, but otherwise not that similar.
	# -- Tim McLean 2018-03-02


	PlanSectionMetricsSelection = React.createFactory React.createClass
		displayName: 'PlanSectionMetricsSelection'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				isCollapsed: false
			}

		render: ->
			isCollapsed = @state.isCollapsed
			section = @props.sectionMetricsData

			return R.div({},
				R.h3({
					className: 'collapsable'
					onClick: @_toggleCollapsed
				},
					FaIcon('angle-up', {className: showWhen not isCollapsed})
					FaIcon('angle-down', {className: showWhen isCollapsed})
					section.get('name')
				)
				R.section({
					className: showWhen(not isCollapsed)
				},
					(section.get('targets').map (target) =>
						PlanTargetMetricsSelection({
							key: target.get('id')
							targetMetricsData: target
							visibleMetricValuesById: @props.visibleMetricValuesById
							selectedMetricIds: @props.selectedMetricIds
							metricColors: @props.metricColors
							updateSelectedMetrics: @props.updateSelectedMetrics
						})
					)
				)
			)

		_toggleCollapsed: ->
			@setState (s) ->
				return {
					isCollapsed: not s.isCollapsed
				}


	PlanTargetMetricsSelection = React.createFactory React.createClass
		displayName: 'PlanTargetMetricsSelection'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				isCollapsed: false
			}

		render: ->
			isCollapsed = @state.isCollapsed
			target = @props.targetMetricsData
			targetId = target.get('id')

			return R.div({
				key: targetId
				className: 'target'
			},
				R.h5({
					className: 'collapsable'
					onClick: @_toggleCollapsed
				},
					FaIcon('angle-up', {className: showWhen not isCollapsed})
					FaIcon('angle-down', {className: showWhen isCollapsed})
					target.get('name')
				)

				(target.get('metrics').map (metric) =>
					metricId = metric.get('id')
					visibleValues = @props.visibleMetricValuesById.get(metricId) or Imm.List()
					isSelected = @props.selectedMetricIds.contains metricId
					metricColor = if @props.metricColors? then @props.metricColors["y-#{metric.get('id')}"]

					R.div({
						key: metricId
						className: 'checkbox metric ' + showWhen(not isCollapsed)
					},
						R.label({},
							ColorKeyCount({
								isSelected
								className: 'circle'
								colorKeyHex: metricColor
								count: visibleValues.count()
							})
							R.input({
								type: 'checkbox'
								onChange: @props.updateSelectedMetrics.bind null, metricId
								checked: isSelected
							})
							metric.get('name')
						)
					)
				)
			)

		_toggleCollapsed: ->
			@setState (s) ->
				return {
					isCollapsed: not s.isCollapsed
				}


	UnassignedMetricsSelection = React.createFactory React.createClass
		displayName: 'UnassignedMetricsSelection'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				isCollapsed: false
			}

		render: ->
			isCollapsed = @state.isCollapsed

			return R.div({className: 'inactive'},
				R.h3({
					className: 'collapsable'
					onClick: @_toggleCollapsed
				},
					FaIcon('angle-up', {className: showWhen not isCollapsed})
					FaIcon('angle-down', {className: showWhen isCollapsed})
					"Inactive"
				)
				R.section({
					className: showWhen(not isCollapsed)
				},
					(@props.unassignedMetricsList.map (metric) =>
						metricId = metric.get('id')
						isSelected = @props.selectedMetricIds.contains metricId
						visibleValues = @props.visibleMetricValuesById.get(metricId) or Imm.List()
						metricColor = if @props.metricColors? then @props.metricColors["y-#{metric.get('id')}"]

						R.div({
							key: metricId
							className: 'checkbox metric'
						},
							R.label({},
								ColorKeyCount({
									isSelected
									className: 'circle'
									colorKeyHex: metricColor
									count: visibleValues.count()
								})
								R.input({
									type: 'checkbox'
									onChange: @props.updateSelectedMetrics.bind null, metricId
									checked: isSelected
								})
								metric.get('name')
							)
						)
					)
				)
			)

		_toggleCollapsed: ->
			@setState (s) ->
				return {
					isCollapsed: not s.isCollapsed
				}


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
