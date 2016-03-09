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
	Gui = win.require 'nw.gui'
	Window = Gui.Window.get(win)

	CrashHandler = require('./crashHandler').load(win)
	MetricWidget = require('./metricWidget').load(win)
	ProgEventsWidget = require('./progEventsWidget').load(win)
	{FaIcon,renderLineBreaks, renderName, renderFileId, showWhen} = require('./utils').load(win)

	PrintPreviewPage = React.createFactory React.createClass
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
		mixins: [React.addons.PureRenderMixin]

		componentDidMount: ->
			# Without timeout, print() triggers before DOM renders
			Window.show()
			Window.focus()
			
			setTimeout ->
				win.print()
			, 1000

		render: ->
			R.div({className: 'printPreview'},				
				(@props.printDataSet.map (printObj) =>					
					clientFile = printObj.get('clientFile')
					data = printObj.get('data')
					progEvents = printObj.get('progEvents')
					title = null

					R.div({className: 'printObj'},
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
								SinglePlanView({
									title: "Care Plan"
									data
									clientFile
									progEvents
								})
							else
								throw new Error "Unknown print-data type: #{setType}"
					)
				).toJS()...
			)


	PrintHeader = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]
		render: ->
			# Calculate timestamp for backdate if exists
			timestamp = Moment(
				@props.data.get('backdate') or @props.data.get('timestamp')
			, Persist.TimestampFormat).format 'MMMM D, YYYY [at] HH:mm'

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
						renderFileId @props.clientFile.get('recordId')
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
							Moment().format 'MMMM D, YYYY [at] HH:mm'
						)
					)
				)
				R.div({className: 'brandLogo'},
					R.div({},
						R.img({
							className: 'logo'
							src: Config.customerLogoLg
						})
					)
				)
			)

	BasicProgNoteView = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]
		render: ->			
			R.div({className: 'basic progNote'},				
				R.div({className: 'notes'},
					renderLineBreaks @props.progNote.get('notes')
				)
			)

	FullProgNoteView = React.createFactory React.createClass
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
									R.h1({}, unit.get 'name')
									R.div({className: "empty #{showWhen unit.get('sections').length is 0}"},
										"This is empty because this #{Term 'plan'} has no #{Term 'sections'}."
									)
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
													R.div({className: 'notes'},
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
								ProgEventsWidget({
									format: 'print'
									data: progEvent
								})
							)
						).toJS()...
					)
				)
			)

	SinglePlanView = React.createFactory React.createClass
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
								(section.get('targetIds').map (targetId) =>
									targets = @props.data.get('targets')
									thisTarget = targets.get(targetId)

									R.div({className: 'target'},
										R.h3({className: 'name'}, thisTarget.get('name'))
										R.div({className: 'notes'}, thisTarget.get('notes'))
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

	return PrintPreviewPage

module.exports = {load}
