# UI logic for the progress note creation window
#
# TODO New plan: create new prognote object/file, trigger update via event bus

_ = require 'underscore'
Async = require 'async'
Imm = require 'immutable'
Moment = require 'moment'

Config = require '../config'

load = (win, {clientId}) ->
	# Libraries from browser context
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM
	Gui = win.require 'nw.gui'
	ExpandingTextArea = require('../expandingTextArea').load(win)
	MetricWidget = require('../metricWidget').load(win)
	ProgNoteDetailView = require('../progNoteDetailView').load(win)
	Spinner = require('../spinner').load(win)
	{FaIcon, renderName, showWhen} = require('../utils').load(win)

	nwWin = Gui.Window.get(win)

	myTemplate = Imm.fromJS Config.templates[Config.useTemplate]

	do ->
		progNote = null
		clientFile = null
		progNotes = null

		init = ->
			render()
			loadData()

		process.nextTick init

		render = ->
			unless progNote?
				React.render Spinner({isOverlay: true}), $('#container')[0]
				return

			React.render new NewProgNotePage({
				progNote
				clientFile
				progNotes
			}), $('#container')[0]

		loadData = ->
			template = myTemplate # TODO
			planTargetsById = null
			metricsById = null

			Async.series [
				(cb) =>
					ActiveSession.persist.clientFiles.readLatestRevisions clientId, 1, (err, revisions) =>
						if err
							cb err
							return

						clientFile = revisions[0]
						cb null
				(cb) =>
					ActiveSession.persist.planTargets.readClientFileTargets clientFile, (err, result) =>
						if err
							cb err
							return

						planTargetsById = result
						cb null
				(cb) =>
					# Figure out which metrics we need to load
					requiredMetricIds = Imm.Set()
					.union template.get('sections').flatMap (section) =>
						switch section.get('type')
							when 'basic'
								return section.get('metricIds')
							when 'plan'
								return []
							else
								throw new Error "unknown section type: #{section.get('type')}"
					.union planTargetsById.valueSeq().flatMap (planTarget) =>
						return planTarget.get('revisions').last().get('metricIds')

					metricsById = Imm.Map()
					Async.each requiredMetricIds.toArray(), (metricId, cb) =>
						ActiveSession.persist.metrics.readLatestRevisions metricId, 1, (err, revisions) =>
							if err
								cb err
								return

							metricsById = metricsById.set metricId, revisions[0]
							cb null
					, cb
				(cb) =>
					ActiveSession.persist.progNotes.readAll clientId, (err, results) =>
						if err
							cb err
							return

						progNotes = Imm.fromJS results
						cb null
			], (err) =>
				if err
					console.error err.stack
					Bootbox.alert "An error occurred while loading the necessary files."
					return

				# Done loading data, we can generate the prognote now
				progNote = createProgNoteFromTemplate(
					template, clientFile, planTargetsById, metricsById
				)

				render()

		createProgNoteFromTemplate = (template, clientFile, planTargetsById, metricsById) ->
			return Imm.fromJS {
				type: 'full'
				author: 'David' # TODO
				clientId: clientFile.get('clientId')
				templateId: template.get('id')
				sections: template.get('sections').map (section) =>
					switch section.get('type')
						when 'basic'
							return Imm.fromJS {
								type: 'basic'
								id: section.get 'id'
								name: section.get 'name'
								notes: ''
								metrics: section.get('metricIds').map (metricId) =>
									m = metricsById.get(metricId)
									return Imm.fromJS {
										id: m.get('id')
										name: m.get('name')
										definition: m.get('definition')
										value: ''
									}
							}
						when 'plan'
							return Imm.fromJS {
								type: 'plan'
								id: section.get 'id'
								name: section.get 'name'
								targets: clientFile.getIn(['plan', 'sections']).flatMap (section) =>
									section.get('targetIds').map (targetId) =>
										target = planTargetsById.get(targetId)
										lastRev = target.get('revisions').last()
										return Imm.fromJS {
											id: target.get 'id'
											name: lastRev.get 'name'
											notes: ''
											metrics: lastRev.get('metricIds').map (metricId) =>
												m = metricsById.get(metricId)
												return Imm.fromJS {
													id: m.get('id')
													name: m.get('name')
													definition: m.get('definition')
													value: ''
												}
										}
							}
			}

	NewProgNotePage = React.createFactory React.createClass
		getInitialState: ->
			return {
				progNote: @props.progNote
				selectedItem: null
				success: false
			}
		render: ->
			return R.div({className: 'newProgNotePage'},
				R.div({className: 'progNote'},
					R.div({className: 'sections'},
						(@state.progNote.get('sections').map (section) =>
							switch section.get('type')
								when 'basic'
									R.div({className: 'basic section', key: section.get('id')},
										R.h1({className: 'name'}, section.get('name'))
										ExpandingTextArea({
											value: section.get('notes')
											onFocus: @_selectBasicSection.bind null, section
											onChange: @_updateBasicSectionNotes.bind null, section.get('id')
										})
										R.div({className: 'metrics'},
											(section.get('metrics').map (metric) =>
												MetricWidget({
													key: metric.get('id')
													name: metric.get('name')
													definition: metric.get('definition')
													onFocus: @_selectBasicSection.bind null, section
													onChange: @_updateBasicSectionMetric.bind(
														null, section.get('id'), metric.get('id')
													)
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
										R.div({className: "empty #{showWhen section.get('targets').size is 0}"},
											"This section is empty because the client has no plan targets."
										)
										R.div({className: 'targets'},
											(section.get('targets').map (target) =>
												R.div({className: 'target', key: target.get('id')},
													R.h2({className: 'name'},
														target.get('name')
													)
													ExpandingTextArea({
														value: target.get('notes')
														onFocus: @_selectPlanSectionTarget.bind(
															null, section, target
														)
														onChange: @_updatePlanSectionNotes.bind(
															null, section.get('id'), target.get('id')
														)
													})
													R.div({className: 'metrics'},
														(target.get('metrics').map (metric) =>
															MetricWidget({
																key: metric.get('id')
																name: metric.get('name')
																definition: metric.get('definition')
																onFocus: @_selectPlanSectionTarget.bind(
																	null, section, target
																)
																onChange: @_updatePlanSectionMetric.bind(
																	null, section.get('id'),
																	target.get('id'), metric.get('id')
																)
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
					R.div({className: 'buttonRow'},
						R.button({
							className: 'save btn btn-primary'
							onClick: @_save
						},
							FaIcon 'check'
							'Save'
						)
					)
				)
				ProgNoteDetailView({
					item: @state.selectedItem
					progNotes: @props.progNotes
				})
			)
		componentDidMount: ->
			clientName = renderName @props.clientFile.get('clientName')
			nwWin.title = "#{clientName}: Progress Note - KoNote"

			nwWin.on 'close', (event) =>
				# TODO
				if @_hasChanges()
					Bootbox.dialog {
						message: "There are unsaved changes in this client file."
						buttons: {
							discard: {
								label: "Discard changes"
								className: 'btn-danger'
								callback: =>
									nwWin.close true
							}
							cancel: {
								label: "Cancel"
								className: 'btn-default'
							}
							save: {
								label: "Save changes"
								className: 'btn-primary'
								callback: =>
									@_save =>
										process.nextTick =>
											nwWin.close()
							}
						}
					}
				else
					nwWin.close(true)
		_hasChanges: ->
			# TODO
		_getSectionIndex: (sectionId) ->
			return @state.progNote.get('sections').findIndex (s) =>
				return s.get('id') is sectionId
		_getTargetIndex: (sectionIndex, targetId) ->
			return @state.progNote.getIn(['sections', sectionIndex, 'targets']).findIndex (t) =>
				return t.get('id') is targetId
		_selectBasicSection: (section) ->
			@setState {
				selectedItem: Imm.fromJS {
					type: 'basicSection'
					sectionId: section.get('id')
					sectionName: section.get('name')
				}
			}
		_selectPlanSectionTarget: (section, target) ->
			@setState {
				selectedItem: Imm.fromJS {
					type: 'planSectionTarget'
					sectionId: section.get('id')
					targetId: target.get('id')
					targetName: target.get('name')
				}
			}
		_updateBasicSectionNotes: (sectionId, event) ->
			sectionIndex = @_getSectionIndex sectionId

			@setState {
				progNote: @state.progNote.setIn ['sections', sectionIndex, 'notes'], event.target.value
			}
		_updateBasicSectionMetric: (sectionId, metricId, newValue) ->
			sectionIndex = @_getSectionIndex sectionId

			metricIndex = @state.progNote.getIn(['sections', sectionIndex, 'metrics']).findIndex (m) =>
				return m.get('id') is metricId

			@setState {
				progNote: @state.progNote.setIn(
					['sections', sectionIndex, 'metrics', metricIndex, 'value']
					newValue
				)
			}
		_updatePlanSectionNotes: (sectionId, targetId, event) ->
			sectionIndex = @_getSectionIndex sectionId

			targetIndex = @state.progNote.getIn(['sections', sectionIndex, 'targets']).findIndex (t) =>
				return t.get('id') is targetId

			@setState {
				progNote: @state.progNote.setIn(
					['sections', sectionIndex, 'targets', targetIndex, 'notes'],
					event.target.value
				)
			}
		_updatePlanSectionMetric: (sectionId, targetId, metricId, newValue) ->
			sectionIndex = @_getSectionIndex sectionId
			targetIndex = @_getTargetIndex sectionIndex, targetId

			metricIndex = @state.progNote.getIn(
				['sections', sectionIndex, 'targets', targetIndex, 'metrics']
			).findIndex (m) =>
				return m.get('id') is metricId

			@setState {
				progNote: @state.progNote.setIn(
					['sections', sectionIndex, 'targets', targetIndex, 'metrics', metricIndex, 'value']
					newValue
				)
			}
		_save: ->
			ActiveSession.persist.progNotes.create @state.progNote, (err) =>
				if err
					console.error err.stack
					Bootbox.alert "An error occurred while saving your progress note."
					return

				@setState {success: true}
				# TODO success animation
				#setTimeout (=> nwWin.close true), 3000
				nwWin.close true

module.exports = {load}
