# UI logic for the progress note creation window

_ = require 'underscore'
Async = require 'async'
Imm = require 'immutable'
Moment = require 'moment'

Config = require '../config'

load = (win, {clientFileId}) ->
	# Libraries from browser context
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	Gui = win.require 'nw.gui'

	CrashHandler = require('../crashHandler').load(win)
	ExpandingTextArea = require('../expandingTextArea').load(win)
	MetricWidget = require('../metricWidget').load(win)
	ProgNoteDetailView = require('../progNoteDetailView').load(win)
	CreateProgEventDialog = require('../createProgEventDialog').load(win)
	Dialog = require('../dialog').load(win)
	LayeredComponentMixin = require('../layeredComponentMixin').load(win)
	Spinner = require('../spinner').load(win)
	{timeoutListeners} = require('../timeoutDialog').load(win)
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
			registerListeners()

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
			planTargetHeaders = null
			progNoteHeaders = null

			Async.series [
				(cb) =>
					ActiveSession.persist.clientFiles.readLatestRevisions clientFileId, 1, (err, revisions) =>
						if err
							cb err
							return

						clientFile = revisions.first()
						cb null
				(cb) =>
					ActiveSession.persist.planTargets.list clientFileId, (err, result) =>
						if err
							cb err
							return

						planTargetHeaders = result
						cb null
				(cb) =>
					Async.map planTargetHeaders.toArray(), (planTargetHeader, cb) ->
						ActiveSession.persist.planTargets.readRevisions clientFileId, planTargetHeader.get('id'), cb
					, (err, planTargets) ->
						if err
							cb err
							return

						pairs = planTargets.map (planTarget) ->
							return [planTarget.getIn([0, 'id']), planTarget]
						planTargetsById = Imm.Map(pairs)

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
						return planTarget.last().get('metricIds')

					metricsById = Imm.Map()
					Async.each requiredMetricIds.toArray(), (metricId, cb) =>
						ActiveSession.persist.metrics.read metricId, (err, result) =>
							if err
								cb err
								return

							metricsById = metricsById.set metricId, result
							cb null
					, cb
				(cb) =>
					ActiveSession.persist.progNotes.list clientFileId, (err, results) =>
						if err
							cb err
							return

						progNoteHeaders = Imm.fromJS results
						cb null
				(cb) =>
					Async.map progNoteHeaders.toArray(), (progNoteHeader, cb) ->
						ActiveSession.persist.progNotes.read clientFileId, progNoteHeader.get('id'), cb
					, (err, results) ->
						if err
							cb err
							return

						progNotes = Imm.List(results)

						cb null
			], (err) =>
				if err
					CrashHandler.handle err
					return

				# Done loading data, we can generate the prognote now
				progNote = createProgNoteFromTemplate(
					template, clientFile, planTargetsById, metricsById
				)

				render()

		registerListeners = ->
			timeoutListeners()

		createProgNoteFromTemplate = (template, clientFile, planTargetsById, metricsById) ->
			return Imm.fromJS {
				type: 'full'
				clientFileId: clientFile.get('id')
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
										lastRev = target.last()
										return Imm.fromJS {
											id: lastRev.get 'id'
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
				progEvents: Imm.List()
				selectedItem: null
				success: false
				showExitAlert: false
			}
		render: ->
			return R.div({className: 'newProgNotePage'},				
				R.div({className: 'progNote'},
					# OpenCreateProgEventButton({
					# 	onNewProgEvent: @_updateProgEvents
					# })
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
				if not @state.showExitAlert
					@setState {showExitAlert: true}
					Bootbox.dialog {
						message: "Are you sure you want to cancel this progress note?"
						buttons: {						
							cancel: {
								label: "Cancel"
								className: 'btn-default'
								callback: =>
									@setState {showExitAlert: false}
							}
							discard: {
								label: "Yes"
								className: 'btn-primary'
								callback: =>
									nwWin.close true
							}
							# save: {
							# 	label: "Save changes"
							# 	className: 'btn-primary'
							# 	callback: =>
							# 		@_save =>
							# 			process.nextTick =>
							# 				nwWin.close()
							# }
						}
					}
		_hasChanges: ->
			# TODO
		_getSectionIndex: (sectionId) ->
			result = @state.progNote.get('sections').findIndex (s) =>
				return s.get('id') is sectionId

			if result is -1
				throw new Error "could not find section with ID #{JSON.stringify sectionId}"

			return result
		_getTargetIndex: (sectionIndex, targetId) ->
			result = @state.progNote.getIn(['sections', sectionIndex, 'targets']).findIndex (t) =>
				return t.get('id') is targetId

			if result is -1
				throw new Error "could not find target with ID #{JSON.stringify targetId}"

			return result
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
		_updateProgEvents: (progEvent) ->
			@setState {
				progEvents: @state.progEvents.push progEvent
			}
			console.log("progEvents updated to:", @state.progEvents)
		_save: ->
			ActiveSession.persist.progNotes.create @state.progNote, (err, obj) =>
				if err
					CrashHandler.handle err
					return

				# Tack on the new progress note ID to all created events					

				modifiedProgEvents = @state.progEvents.map (progEvent) ->
					return progEvent.set('relatedProgNoteId', obj.get('id'))

				console.log("Modified progEvents:", modifiedProgEvents)


				Async.each modifiedProgEvents.toArray(), (progEvent, cb) =>		
					ActiveSession.persist.progEvents.create progEvent, cb
				, (err, results) =>
					if (err)
						CrashHandler.handle err
						return					

					@setState {success: true}
					# TODO success animation
					#setTimeout (=> nwWin.close true), 3000
					nwWin.close true



	OpenCreateProgEventButton = React.createFactory React.createClass
		mixins: [LayeredComponentMixin]
		getInitialState: ->
			return {
				isOpen: false
			}
		render: ->
			return R.button({
				className: 'btn btn-success'
				onClick: @_open
			},
				FaIcon 'bell'
				"Create Event"
			)
		renderLayer: ->
			unless @state.isOpen
				return R.div()

			return CreateProgEventDialog({
				onCancel: =>
					@setState {isOpen: false}		
				onSuccess: (progEvent) =>							
					@setState {isOpen: false}
					@props.onNewProgEvent progEvent
			})
		_open: ->
			@setState {isOpen: true}

module.exports = {load}
