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

	CrashHandler = require('./crashHandler').load(win)
	MetricWidget = require('./metricWidget').load(win)
	{FaIcon,renderLineBreaks, renderName, renderFileId, showWhen} = require('./utils').load(win)

	PrintPreviewPage = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				printDataSet: Imm.fromJS JSON.parse(dataSet)
			}

		init: -> # Do nothing
		deinit: -> # Do nothing

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
			setTimeout ->
				win.print()
			, 500

		render: ->
			R.div({className: 'printPreview'},				
				(@props.printDataSet.map (printObj) =>					
					clientFile = printObj.get('clientFile')
					data = printObj.get('data')
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
										})
									when 'full'
										FullProgNoteView({
											progNote: data
											clientFile
										})
									else
										throw new Error "Unknown progNote type: #{progNote.get('type')}"
							when 'plan'
								SinglePlanView({
									title: "Care Plan"
									data
									clientFile
								})
							else
								throw new Error "Unknown print-data type: #{setType}"
					)
				).toJS()...
			)


	PrintHeader = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]
		render: ->
			R.div({className: 'header'},
				R.div({className: 'leftSide'},
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
				R.div({className: 'rightSide'},
					R.img({
						className: 'logo'
						src: 'customer-logo-lg.png'
					})
					(if @props.format isnt 'plan'
						R.ul({},
							R.li({}, 
								FaIcon('user')
								"Authored by: "
								# TODO: Include user's full name + username ("Andrew Appleby (aappleby)")
								R.span({className: 'author'}, @props.data.get('author'))
							)
							R.li({className: 'date'},
								Moment(@props.data.get('timestamp'), Persist.TimestampFormat)
								.format 'MMMM D, YYYY [at] HH:mm'
							)
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
				R.div({className: 'sections'},
					(@props.progNote.get('sections').map (section) =>
						switch section.get('type')
							when 'basic'
								R.div({className: 'basic section', key: section.get('id')},
									R.h1({
										className: 'name'
									},
										section.get('name')
									)
									R.div({className: "empty #{showWhen section.get('notes').length is 0}"},
										'(blank)'
									)
									R.div({className: 'notes'},
										renderLineBreaks section.get('notes')
									)
									R.div({className: 'metrics'},
										(section.get('metrics').map (metric) =>
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
								R.div({className: 'plan section', key: section.get('id')},
									R.h1({className: 'name'},
										section.get('name')
									)
									R.div({className: "empty #{showWhen section.get('targets') is ''}"},
										"This #{Term 'section'} is empty because the #{Term 'client'} has no #{Term 'plan targets'}."
									)
									R.div({className: 'targets'},
										(section.get('targets').map (target) =>
											R.div({
												className: 'target'
												key: target.get('id')
											},
												R.h2({className: 'name'},target.get('name'))
												R.div({className: "empty #{showWhen target.get('notes') is ''}"},
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
								)
					).toJS()...
				)
			)

	SinglePlanView = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]
		render: ->
			R.div({className: 'plan'},
				R.div({className: 'sections'},
					(@props.data.get('sections').map (section) =>
						R.div({className: 'section planTargets', key: section.get('id')},
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