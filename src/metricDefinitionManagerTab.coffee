# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Tab layer for adding/defining or managing existing metric definitions

_ = require 'underscore'
Async = require 'async'
Parse = require 'csv-parse'
Fs = require 'fs'
Imm = require 'immutable'
Path = require 'path'

Persist = require './persist'
Term = require './term'


load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	# TODO: Refactor to single require
	{BootstrapTable, TableHeaderColumn} = win.ReactBootstrapTable
	BootstrapTable = React.createFactory BootstrapTable
	TableHeaderColumn = React.createFactory TableHeaderColumn

	CrashHandler = require('./crashHandler').load(win)
	Dialog = require('./dialog').load(win)
	OpenDialogLink = require('./openDialogLink').load(win)
	DefineMetricDialog = require('./defineMetricDialog').load(win)
	DialogLayer = require('./dialogLayer').load(win)

	{
		maxMetricNameLength, FaIcon, showWhen, stripMetadata, renderName
	} = require('./utils').load(win)


	MetricDefinitionManagerTab = React.createFactory React.createClass
		displayName: 'MetricDefinitionManagerTab'
		mixins: [React.addons.PureRenderMixin]
		# TODO: propTypes

		getInitialState: -> {
			displayInactive: false
		}

		render: ->
			unless @props.metricsById
				# Probably won't ever appear, since metrics are loaded in the background
				return R.div({
					className: 'metricDefinitionManagerTab loading'
				}, "Loading...")

			isAdmin = global.ActiveSession.isAdmin()

			# Get list of all metrics
			metricDefinitions = @props.metricsById.valueSeq()
				.map((m) -> stripMetadata m)

			# Determine inactive metrics
			inactiveMetricDefinitions = metricDefinitions
				.filter (metric) ->
					metric.get('status') isnt 'default'

			hasInactiveMetrics = not inactiveMetricDefinitions.isEmpty()
			hasData = not metricDefinitions.isEmpty()

			# Configure table data
			tableData = metricDefinitions

			# UI Filters
			unless @state.displayInactive
				tableData = tableData.filter (metric) -> metric.get('status') is 'default'

			# Table display formats (TODO: extract to a tableWrapper component)
			# Convert 'default' -> 'active' for table display (TODO: Term)
			tableData = tableData.map (metric) ->
				if metric.get('status') is 'default'
					return metric.set('status', 'active')

				return metric

			return R.div({className: 'metricDefinitionManagerTab'},
				R.div({className: 'header'},
					R.h1({},
						R.div({className: 'optionsMenu'},
							R.input({
								className: 'form-control'
								id: 'searchBar'
								placeholder: "Search #{Term 'Metrics'}"
								onChange: @_handleTableSearch
							})

							(if isAdmin
								OpenDialogLink({
									className: 'btn btn-primary'
									dialog: DefineMetricDialog
								},
									FaIcon('plus')
									" New #{Term 'Metric'}"
								)
							)

							(if hasInactiveMetrics
								R.div({className: 'toggleInactive'},
									R.label({},
										"Show inactive (#{inactiveMetricDefinitions.count()})"
										R.input({
											type: 'checkbox'
											checked: @state.displayInactive
											onClick: @_toggleDisplayInactive
										})
									)
								)
							)
						)
						"#{Term 'Metric Definitions'}"
					)
				)
				R.div({className: 'main'},
					(if hasData
						R.div({className: 'responsiveTable animated fadeIn'},
							DialogLayer({
								ref: 'dialogLayer'
								metricsById: @props.metricsById
							},
								BootstrapTable({
									ref: 'metricTable'
									data: tableData.toJS()
									keyField: 'id'
									bordered: false
									options: {
										defaultSortName: 'name'
										defaultSortOrder: 'asc'
										searchPosition: 'right'
										onRowClick: ({id}) =>
											return unless isAdmin

											@refs.dialogLayer.open ModifyMetricDialog, {
												metricId: id
											}
										noDataText: "No #{Term 'metric definitions'} to display"
									}
									trClassName: (row) -> 'inactive' if row.status isnt 'active'
								},
									TableHeaderColumn({
										dataField: 'id'
										className: 'colorKeyColumn'
										columnClassName: 'colorKeyColumn'
										dataFormat: -> null
									})
									TableHeaderColumn({
										dataField: 'name'
										className: 'nameColumn'
										columnClassName: 'nameColumn'
										dataSort: true
									}, "#{Term 'Metric'} Name")
									TableHeaderColumn({
										dataField: 'definition'
										className: [
											'descriptionColumn'
											'rightPadding' unless @state.displayInactive
										].join ' '
										columnClassName: [
											'descriptionColumn'
											'rightPadding' unless @state.displayInactive
										].join ' '
									}, "Definition")
									TableHeaderColumn({
										dataField: 'status'
										className: [
											'statusColumn'
											'rightPadding' if @state.displayInactive
										].join ' '
										columnClassName: [
											'statusColumn'
											'rightPadding' if @state.displayInactive
										].join ' '
										dataSort: true
										hidden: not @state.displayInactive
										headerAlign: 'right'
										dataAlign: 'right'
									}, "Status")
								)
							)
						)
					else
						R.div({className: 'noData'},
							R.span({className: 'animated fadeInUp'},
								"No #{Term 'metric definitions'} exist yet"
							)
						)
					)
				)
				R.div({className: 'footer'},
					R.a({
						className: 'importMetricsLink'
						href: "#"
						onClick: @_importMetrics
					},
						"Import #{Term 'metric definitions'}..."
					)
					R.input({
						type: 'file'
						className: 'hidden'
						ref: 'importMetricsInput'
					})
				)
			)

		_handleTableSearch: (event) ->
			@refs.metricTable.handleSearch(event.target.value)

		_toggleDisplayInactive: ->
			displayInactive = not @state.displayInactive
			@setState {displayInactive}

		_importMetrics: (event) ->
			event.preventDefault()

			filePath = null
			csv = null
			metricsToCreate = null
			existingMetricNames = null
			existingMetricCustomIds = null

			Async.series [
				(cb) ->
					Bootbox.alert "Select a CSV file with three columns: metric name, metric definition, and metric ID (optional).", ->
						cb()
				(cb) =>
					$(@refs.importMetricsInput)
					.off()
					.val('')
					.attr('accept', ".csv")
					.on 'change', (event) =>
						filePath = event.target.value
						console.log "Import metric defs from " + JSON.stringify(filePath)
						cb()
					.click()
				(cb) ->
					Fs.readFile filePath, 'utf8', (err, rawCsv) ->
						if err
							console.error err
							console.error err.stack
							Bootbox.alert("An error occured while reading the file at " + filePath)
							return

						# strip utf-8 byte-order-mark
						csv = rawCsv.replace(/^\ufeff/, "");
						cb()
				(cb) ->

					Parse(csv,{skip_empty_lines: true, skip_lines_with_empty_values:true, trim:true, columns:['name','definition','customId']}, (err, results) =>
						if err
							console.error err
							Bootbox.alert("The selected file does not seem to be a valid CSV file.")
							return

						if results.length is 0
							Bootbox.alert "The selected file seems to be empty."
							return

						for m in results
							if m.name is ''
								Bootbox.alert "The selected file contains a metric with an empty name."
								return

							if m.name.length > maxMetricNameLength
								Bootbox.alert "Metric names must be " + maxMetricNameLength +
									" characters or less. \"#{m.name}\" is an invalid name."
								return

							if m.definition is ''
								Bootbox.alert "The selected file contains a metric with an empty definition."
								return

						metricsToCreate = Imm.fromJS results

						cb()
					)

				(cb) ->
					# Get names of existing metrics
					ActiveSession.persist.metrics.list (err, result) ->
						if err
							if err instanceof Persist.IOError
								Bootbox.alert """
									Please check your network connection and try again.
								"""
								return

							CrashHandler.handle err
							return

						existingMetricNames = result
							.map (metric) -> metric.get('name').trim().toLowerCase()
							.toSet()

						existingMetricCustomIds = result
							.map (metric) -> metric.get('customId').trim().toLowerCase()
							.toSet()

						cb()
				(cb) ->
					metricsToCreateNames = metricsToCreate
						.map (m) -> m.get('name').trim().toLowerCase()
					metricsToCreateNamesSet = metricsToCreateNames.toSet()

					metricsToCreateCustomIds = metricsToCreate
						.map (m) -> m.get('customId').trim().toLowerCase()
					.filter(Boolean)

					metricsToCreateCustomIdsSet = metricsToCreateCustomIds.toSet()

					console.log metricsToCreateCustomIds.toJS()

					# If there are duplicate IDs in the input CSV
					if metricsToCreateCustomIds.size isnt metricsToCreateCustomIdsSet.size
						duplicatedCustomIds = metricsToCreateCustomIds
							.countBy (customId) -> customId
							.filter (occurrences) -> (occurrences > 1)
							.keySeq()
						Bootbox.alert R.div({},
							"Could not complete import. The CSV file contains duplicate metric IDs:",
							R.br(),R.br(),
							R.ul({},
								(duplicatedCustomIds
									.sort()
									.map (customId) -> R.li({}, customId)
									.toArray()
								)...
							)
						)
						return

					# If there are duplicate metric names in the input file
					if metricsToCreateNames.size isnt metricsToCreateNamesSet.size
						duplicatedNames = metricsToCreateNames
							.countBy (name) -> name
							.filter (occurrences) -> (occurrences > 1)
							.keySeq()

						Bootbox.alert R.div({},
							"Could not complete import. ",
							"The CSV file contains duplicate definitions of the following metrics:",
							R.ul({},
								(duplicatedNames
									.sort()
									.map (name) -> R.li({}, name)
									.toArray()
								)...
							)
						)
						return

					overlappingNames = metricsToCreateNamesSet.intersect(existingMetricNames)
					overlappingCustomIds = metricsToCreateCustomIdsSet.intersect(existingMetricCustomIds)

					# If any metrics in the input file already exist
					if overlappingCustomIds.size > 0
						console.log overlappingCustomIds.toJS()
						console.log metricsToCreate.toJS()
						Bootbox.alert R.div({},
							"Could not complete import. The file contains metric IDs that are already in use:",
							R.br(),R.br(),
							R.ul({},
								(overlappingCustomIds
									.sort()
									.map (customId) ->
										R.li({}, customId)
									)
							)
						)
						return

					if overlappingNames.size > 0
						Bootbox.alert R.div({},
							"Could not complete import. The following metric names are already in use:",
							R.ul({},
								(overlappingNames
									.sort()
									.map (name) ->
										R.li({}, name)
									)
							)
						)
						return

					cb()
				(cb) ->
					firstEntry = metricsToCreate.first()
					Bootbox.dialog {
						title: 'Import metric definitions file'
						message: R.div({},
							"#{metricsToCreate.size} metric definition(s) were found in \"",
							Path.basename(filePath),
							'".',
							R.br(), R.br(),
							"Please check that the first metric definition to be imported appears ",
							"correctly below:",
							R.ul({},
								R.li({},
									R.strong({}, "Name"),
									": ", firstEntry.get('name')
								)
								R.li({},
									R.strong({}, "Description"),
									": ", firstEntry.get('definition')
								)
								R.li({},
									R.strong({}, "ID (optional)"),
									": ", firstEntry.get('customId')
								)
							)
						)
						buttons: {
							cancel: {
								label: 'Cancel'
								className: 'btn-default'
							}
							continue: {
								label: (
									if metricsToCreate.size is 1
										'Import 1 metric'
									else
										"Import #{metricsToCreate.size} metrics"
								)
								className: 'btn-primary'
								callback: -> cb()
							}
						}
					}
				(cb) ->
					Async.eachLimit metricsToCreate.toArray(), 20, (metricToCreate, cb) ->
						newMetric = Imm.Map({
							name: metricToCreate.get('name')
							definition: metricToCreate.get('definition')
							customId: metricToCreate.get('customId')
							status: 'default'
						})

						ActiveSession.persist.metrics.create newMetric, (err, result) =>
							if err
								cb err
								return

							cb()
					, (err) ->
						if err
							if err instanceof Persist.IOError
								Bootbox.alert """
									Please check your network connection and try again.
								"""
								return

							CrashHandler.handle err
							return

						cb()
				(cb) ->
					Bootbox.alert "Import finished successfully.", -> cb()
			], (err) ->
				if err
					console.error "Unexpected error during metric import"
					console.error err
					console.error err.stack
					throw err

				# OK


	ModifyMetricDialog = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			metric = @props.metricsById.get(@props.metricId)

			return {
				name: metric.get('name')
				definition: metric.get('definition')
				customId: metric.get('customId') or ''
				status: metric.get('status')
			}

		componentDidMount: ->
			@refs.nameField.focus()

		render: ->
			Dialog({
				ref: 'dialog'
				title: "Modify #{Term 'Metric'} Definition"
				onClose: @_cancel
			},
				R.div({className: 'defineMetricDialog'},
					R.div({className: 'form-group'},
						R.label({}, "Name")
						R.input({
							ref: 'nameField'
							className: 'form-control'
							onChange: @_updateName
							value: @state.name
							maxLength: maxMetricNameLength
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "Definition")
						R.textarea({
							className: 'form-control'
							placeholder: "Define the #{Term 'metric'}"
							value: @state.definition
							onChange: @_updateDefinition
							rows: 5
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "#{Term 'Custom Id'}"),
						R.input({
							ref: 'customIdField'
							className: 'form-control'
							onChange: @_updateCustomId
							value: @state.customId
							placeholder: "Unique ID (optional)"
							maxLength: maxMetricNameLength
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "#{Term 'Metric'} Status"),
						R.div({className: 'btn-toolbar'},
							R.button({
								className:
									if @state.status is 'default'
										'btn btn-success'
									else 'btn btn-default'
								onClick: @_updateStatus
								value: 'default'
							},
								"Active"
							)
							R.button({
								className:
									'btn btn-' + if @state.status is 'deactivated'
										'danger'
									else
										'default'
								onClick: @_updateStatus
								value: 'deactivated'
							},
								"Deactivated"
							)
						)
					)
					R.div({className: 'btn-toolbar pull-right'},
						R.button({
							className: 'btn btn-default'
							onClick: @_cancel
						}, "Cancel"),
						R.button({
							className: 'btn btn-primary'
							onClick: @_submit
						}, "Modify #{Term 'Metric'}")
					)
				)
			)

		_cancel: ->
			@props.onCancel()

		_updateName: (event) ->
			@setState {name: event.target.value}

		_updateDefinition: (event) ->
			@setState {definition: event.target.value}

		_updateCustomId: (event) ->
			@setState {customId: event.target.value}

		_updateStatus: (event) ->
			@setState {status: event.target.value}

		_submit: ->
			name = @state.name.trim()
			definition = @state.definition.trim()
			customId = @state.customId.trim()
			status = @state.status

			unless name
				Bootbox.alert "#{Term 'Metric'} name is required"
				return

			unless definition
				Bootbox.alert "#{Term 'Metric'} definition is required"
				return

			if customId
				return Bootbox.confirm "You are modifying a metric with a standard definition. Are you sure?", (ok) =>
					if ok then @_submitMetric name, definition, customId, status

			@_submitMetric name, definition, customId, status

		_submitMetric: (name, definition, customId, status) ->

			@refs.dialog.setIsLoading true

			result = null

			Async.series [
				(cb) =>
					# Look for an existing metric with the same name
					ActiveSession.persist.metrics.list (err, metricHeaders) =>
						if err
							cb err
							return

						existingMetricWithName = metricHeaders.find (m) =>
							return m.get('name').toLowerCase() is name.toLowerCase() and m.get('id') isnt @props.metricId

						if existingMetricWithName
							@refs.dialog.setIsLoading(false) if @refs.dialog?
							Bootbox.alert "There is already a metric called \"#{name}\"."
							return

						existingMetricWithId = metricHeaders.find (m) =>
							return customId and m.get('customId') is customId and m.get('id') isnt @props.metricId

						if existingMetricWithId
							@refs.dialog.setIsLoading(false) if @refs.dialog?
							Bootbox.alert "There is already a metric with that #{Term 'custom id'}."
							return

						cb()
				(cb) =>
					newMetricRevision = Imm.Map({
						id: @props.metricId
						name, definition, customId, status
					})

					ActiveSession.persist.metrics.createRevision newMetricRevision, (err, newRev) =>
						if err
							cb err
							return

						result = newRev
						cb()
			], (err) =>
				@refs.dialog.setIsLoading(false) if @refs.dialog?

				if err
					if err instanceof Persist.IOError
						Bootbox.alert """
							Please check your network connection and try again.
						"""
						return

					CrashHandler.handle err
					return

				@props.onSuccess(result)


	return MetricDefinitionManagerTab

module.exports = {load}
