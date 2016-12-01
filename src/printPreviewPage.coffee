# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Print preview page receives data from the printButton's data,
# and matches printing components with the type(s) of data received

Imm = require 'immutable'
Moment = require 'moment'

Config = require './config'
Term = require './term'
Persist = require './persist'

load = (win, {dataSet}) ->
	$ = win.jQuery
	React = win.React
	R = React.DOM
	Window = nw.Window.get(win)

	CrashHandler = require('./crashHandler').load(win)
	MetricWidget = require('./metricWidget').load(win)
	ProgEventWidget = require('./progEventWidget').load(win)
	ExpandedMetricWidget = require('./expandedMetricWidget').load(win)
	{FaIcon,renderLineBreaks, renderName,
	renderRecordId, showWhen, formatTimestamp} = require('./utils').load(win)

	PrintPreviewPage = React.createFactory React.createClass
		displayName: 'PrintPreviewPage'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				printDataSet: Imm.fromJS JSON.parse(dataSet)
			}

		init: -> # Do nothing
		deinit: (cb=(->)) ->
			# Do nothing
			cb()

		suggestClose: ->
			@props.closeWindow()

		getPageListeners: -> {}

		render: ->
			new PrintPreviewPageUi {
				printDataSet: @state.printDataSet
			}

	PrintPreviewPageUi = React.createFactory React.createClass
		displayName: 'PrintPreviewPageUi'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				previewType: 'default'
			}

		render: ->
			R.div({className: 'printPreview'},
				(@props.printDataSet.map (printObj) =>
					clientFile = printObj.get('clientFile')
					data = printObj.get('data')
					progEvents = printObj.get('progEvents')
					title = null


					R.div({className: 'printObj'},
						R.div({className: 'noPrint'},
							R.button({
								ref: 'print'
								className: 'print btn btn-primary'
								onClick: win.print
							},
								FaIcon('print')
								" "
								"Print"
							)

							(if printObj.get('format') is 'plan'
								R.div({className: 'toggle btn-group btn-group-sm'},
									R.button({
										ref: 'print'
										className: 'default btn btn-primary'
										onClick: @_togglePreviewType
										disabled: @state.previewType is 'default'
									},
										"Default"
									)
									R.button({
										ref: 'print'
										className: 'cheatSheet btn btn-primary'
										onClick: @_togglePreviewType
										disabled: @state.previewType is 'cheatSheet'
									},
										"Cheat Sheet"
									)
								)
							)
						)

						PrintHeader({
							data
							format: printObj.get('format')
							clientFile: clientFile
						})
						switch printObj.get('format')
							when 'progNote'
								switch data.get('type')
									when 'basic'
										BasicProgNoteView({
											progNote: data
											clientFile
											progEvents
										})
									when 'full'
										FullProgNoteView({
											progNote: data
											clientFile
											progEvents
										})
									else
										throw new Error "Unknown progNote type: #{progNote.get('type')}"
							when 'plan'
								if @state.previewType is 'default'
									SinglePlanView({
										title: "Care Plan"
										data
										clientFile
										progEvents
									})
								else if @state.previewType is 'cheatSheet'
									CheatSheetPlanView({
										title: "Care Plan"
										data
										clientFile
										progEvents
									})


							else
								throw new Error "Unknown print-data type: #{setType}"
						R.footer({className: 'footer'},
							R.div({className: 'content'}
								"LOREM IPSUM"
							)
						)
					)
				).toJS()...
			)

		_togglePreviewType: ->
			unless @state.previewType is 'default'
				@setState {previewType: 'default'}
				return
			@setState {previewType: 'cheatSheet'}



	PrintHeader = React.createFactory React.createClass
		displayName: 'PrintHeader'
		mixins: [React.addons.PureRenderMixin]
		render: ->
			# Calculate timestamp for backdate if exists
			timestamp = formatTimestamp(@props.data.get('backdate') or @props.data.get('timestamp'))

			if @props.data.get('backdate') then timestamp  = "(late entry) #{timestamp}"

			return R.header({className: 'header'},
				R.div({className: 'basicInfo'},
					R.h1({className: 'title'},
						FaIcon('pencil-square-o')
						switch @props.format
							when 'progNote' then "Progress Note"
							when 'plan' then "Care Plan"
					)
					R.h3({className: 'clientName'},
						renderName @props.clientFile.get('clientName')
					)
					R.span({className: 'clientRecordId'},
						renderRecordId @props.clientFile.get('recordId')
					)
				)
				R.div({className: 'authorInfo'},
					(if @props.format isnt 'plan'
						R.ul({},
							R.li({},
								FaIcon('user')
								"Authored by: "
								# TODO: Include user's full name + username ("Andrew Appleby (aappleby)")
								R.span({className: 'author'}, @props.data.get('author'))
							)
							R.li({className: 'date'}, timestamp)
						)
					)
					R.ul({},
						R.li({},
							FaIcon('print')
							"Printed by: "
							# TODO: Include user's full name + username ("Andrew Appleby (aappleby)")
							R.span({className: 'author'}, global.ActiveSession.userName)
						)
						R.li({className: 'date'},
							Moment().format 'Do MMM, YYYY [at] h:mma'
						)
					)
				)
				R.div({className: 'brandLogo'},
					R.div({},
						R.img({
							className: 'logo'
							src: Config.logoCustomerLg
						})
					)
				)
			)

	BasicProgNoteView = React.createFactory React.createClass
		displayName: 'BasicProgNoteView'
		mixins: [React.addons.PureRenderMixin]
		render: ->
			R.div({className: 'basic progNote'},
				R.div({className: 'notes'},
					renderLineBreaks @props.progNote.get('notes')
				)
			)

	FullProgNoteView = React.createFactory React.createClass
		displayName: 'FullProgNoteView'
		mixins: [React.addons.PureRenderMixin]
		render: ->
			R.div({className: 'full progNote'},
				R.div({className: 'units'},
					(@props.progNote.get('units').map (unit) =>
						switch unit.get('type')
							when 'basic'
								R.div({
									className: 'basic unit'
									key: unit.get('id')
								},
									R.h3({}, unit.get 'name')
									R.div({className: "empty #{showWhen unit.get('notes').length is 0}"},
										'(blank)'
									)
									R.div({className: 'notes'},
										renderLineBreaks unit.get('notes')
									)
									R.div({className: 'metrics'},
										(unit.get('metrics').map (metric) =>
											MetricWidget({
												isEditable: false
												key: metric.get('id')
												name: metric.get('name')
												definition: metric.get('definition')
												value: metric.get('value')
											})
										).toJS()...
									)
								)
							when 'plan'
								R.div({className: 'plan unit', key: unit.get('id')},
									(unit.get('sections').map (section) =>
										R.section({},
											R.h2({}, section.get 'name')
											(section.get('targets').map (target) =>
												R.div({
													className: 'target'
													key: target.get('id')
												},
													R.h3({}, target.get('name'))
													R.div({className: "empty #{showWhen not target.get('notes')}"},
														'(blank)'
													)
													R.div({className: 'description'},
														renderLineBreaks target.get('notes')
													)
													R.div({className: 'metrics'},
														(target.get('metrics').map (metric) =>
															MetricWidget({
																isEditable: false
																key: metric.get('id')
																name: metric.get('name')
																definition: metric.get('definition')
																value: metric.get('value')
															})
														).toJS()...
													)
												)
											).toJS()...
										)
									).toJS()...
								)
					).toJS()...
				)
				(unless @props.progEvents.isEmpty()
					R.div({className: 'progEvents'},
						R.h3({}, Term 'Events')
						(@props.progEvents.map (progEvent) =>
							R.div({}
								ProgEventWidget({
									format: 'print'
									progEvent
								})
							)
						).toJS()...
					)
				)
			)

	SinglePlanView = React.createFactory React.createClass
		displayName: 'SinglePlanView'
		mixins: [React.addons.PureRenderMixin]
		render: ->
			R.div({className: 'plan unit'},
				R.div({className: 'sections'},
					(@props.data.get('sections').map (section) =>
						R.section({className: 'section planTargets', key: section.get('id')},
							R.h2({className: 'name'}, section.get('name'))
							(if section.get('targetIds').size is 0
								R.div({className: 'noTargets'},
									"This #{Term 'section'} is empty."
								)
							)
							R.div({className: 'targets'},
								(section.get('targetIds')
								.filter (targetId) =>
									targets = @props.data.get('targets')
									thisTarget = targets.get(targetId)
									return thisTarget.get('status') is 'default'
								.map (targetId) =>
									targets = @props.data.get('targets')
									thisTarget = targets.get(targetId)

									R.div({className: 'target'},
										R.h3({className: 'name'}, thisTarget.get('name'))
										R.div({className: 'description'}, thisTarget.get('description'))
										R.div({className: 'metrics'},
											(thisTarget.get('metricIds').map (metricId) =>
												metric = @props.data.get('metrics').get(metricId)
												MetricWidget({
													name: metric.get('name')
													definition: metric.get('definition')
													value: metric.get('value')
													key: metricId
												})
											).toJS()...
										)
									)
								).toJS()...
							)
						)
					).toJS()...
				)
			)

	CheatSheetPlanView = React.createFactory React.createClass
		displayName: 'SinglePlanView'
		mixins: [React.addons.PureRenderMixin]
		render: ->
			R.div({className: 'plan unit'},
				R.div({className: 'sections'},
					(@props.data.get('sections')
					.filter (section) =>
						section.get('status') is 'default'

					.map (section) =>
						R.section({className: 'section planTargets', key: section.get('id')},
							R.h2({className: 'name'}, section.get('name'))
							(if section.get('targetIds').size is 0
								R.div({className: 'noTargets'},
									"This #{Term 'section'} is empty."
								)
							)
							R.div({className: 'targets'},
								(section.get('targetIds')
								.filter (targetId) =>
									targets = @props.data.get('targets')
									thisTarget = targets.get(targetId)
									return thisTarget.get('status') is 'default'
								.map (targetId) =>
									targets = @props.data.get('targets')
									thisTarget = targets.get(targetId)

									R.div({className: 'target'},
										R.h3({className: 'name'}, thisTarget.get('name'))
										R.div({className: 'description'}, thisTarget.get('description'))
										R.div({className: 'cheatMetrics'},
											(thisTarget.get('metricIds').map (metricId) =>
												metric = @props.data.get('metrics').get(metricId)
												ExpandedMetricWidget({
													name: metric.get('name')
													definition: metric.get('definition')
													value: metric.get('value')
													key: metricId
												})
											).toJS()...
										)
									)
								).toJS()...
							)
						)
					).toJS()...
				)
			)

	return PrintPreviewPage

module.exports = {load}
