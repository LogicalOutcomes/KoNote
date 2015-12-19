# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# UI logic for the progress note creation window

Async = require 'async'
Imm = require 'immutable'
Moment = require 'moment'
_ = require 'underscore'

Config = require '../config'
Term = require '../term'
Persist = require '../persist'

load = (win, {clientFileId}) ->
	# Libraries from browser context
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	Gui = win.require 'nw.gui'

	EventTabView = require('./eventTabView').load(win)
	CrashHandler = require('../crashHandler').load(win)
	ExpandingTextArea = require('../expandingTextArea').load(win)
	MetricWidget = require('../metricWidget').load(win)
	ProgNoteDetailView = require('../progNoteDetailView').load(win)	
	Dialog = require('../dialog').load(win)
	LayeredComponentMixin = require('../layeredComponentMixin').load(win)
	Spinner = require('../spinner').load(win)
	{FaIcon, renderName, showWhen} = require('../utils').load(win)

	progNoteTemplate = Imm.fromJS Config.templates[Config.useTemplate]

	NewProgNotePage = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				isLoading: true
				loadErrorType: null
				progNote: null
				clientFile: null
				progNoteHistories: null
			}

		init: ->
			@_loadData()

		deinit: (cb=(->)) ->
			cb()
			# Nothing need be done

		getPageListeners: -> {}

		suggestClose: ->
			@refs.ui.suggestClose()

		render: ->
			new NewProgNotePageUi({
				ref: 'ui'

				isLoading: @state.isLoading
				loadErrorType: @state.loadErrorType
				progNote: @state.progNote
				clientFile: @state.clientFile
				progNoteHistories: @state.progNoteHistories
				progEvents: @state.progEvents

				closeWindow: @props.closeWindow
				setWindowTitle: @props.setWindowTitle
			})

		_loadData: ->
			template = progNoteTemplate

			planTargetsById = null
			metricsById = null
			planTargetHeaders = null
			progNoteHeaders = null
			progEventHeaders = null

			Async.series [
				(cb) =>
					ActiveSession.persist.clientFiles.readLatestRevisions clientFileId, 1, (err, revisions) =>
						if err
							cb err
							return

						@setState (state) =>
							return {clientFile: revisions.first()}

						cb null
				(cb) =>
					ActiveSession.persist.planTargets.list clientFileId, (err, result) =>
						if err
							cb err
							return

						planTargetHeaders = result
						cb null
				(cb) =>
					Async.map planTargetHeaders.toArray(), (planTargetHeader, cb) =>
						ActiveSession.persist.planTargets.readRevisions clientFileId, planTargetHeader.get('id'), cb
					, (err, planTargets) ->
						if err
							cb err
							return

						pairs = planTargets.map (planTarget) =>
							return [planTarget.getIn([0, 'id']), planTarget]
						planTargetsById = Imm.Map(pairs)

						cb null
				(cb) =>
					# Figure out which metrics we need to load
					requiredMetricIds = Imm.Set()
					.union template.get('units').flatMap (section) =>
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
					Async.map progNoteHeaders.toArray(), (progNoteHeader, cb) =>
						ActiveSession.persist.progNotes.readRevisions clientFileId, progNoteHeader.get('id'), cb
					, (err, results) =>
						if err
							cb err
							return

						@setState (state) =>
							return {progNoteHistories: Imm.List(results)}

						cb null
				(cb) =>
					ActiveSession.persist.progEvents.list clientFileId, (err, results) =>
						if err
							cb err
							return

						progEventHeaders = results

						cb()
				(cb) =>
					Async.map progEventHeaders.toArray(), (progEventHeader, cb) =>
						ActiveSession.persist.progEvents.read clientFileId, progEventHeader.get('id'), cb
					, (err, results) =>
						if err
							cb err
							return

						@setState {
							progEvents: Imm.List(results)
						}, cb
			], (err) =>
				if err
					if err instanceof Persist.IOError
						@setState =>
							return {
								isLoading: false
								loadErrorType: 'io-error'
							}
						@render()
						return

					CrashHandler.handle err
					return

				progNote = @_createProgNoteFromTemplate(
					template
					@state.clientFile
					planTargetsById
					metricsById
				)

				console.info "progNote", progNote.toJS()

				# Done loading data, we can load in the empty progNote object
				@setState {
					isLoading: false
					progNote
				}

		_createProgNoteFromTemplate: (template, clientFile, planTargetsById, metricsById) ->
			return Imm.fromJS {
				type: 'full'
				status: 'default'
				clientFileId: clientFile.get('id')
				templateId: template.get('id')
				backdate: ''
				units: template.get('units').map (unit) =>
					switch unit.get('type')
						when 'basic'
							return Imm.fromJS {
								type: 'basic'
								id: unit.get 'id'
								name: unit.get 'name'
								notes: ''
								metrics: unit.get('metricIds').map (metricId) =>
									metric = metricsById.get metricId

									return Imm.fromJS {
										id: metric.get 'id'
										name: metric.get 'name'
										definition: metric.get 'definition'
										value: ''
									}
							}
						when 'plan'							
							return Imm.fromJS {
								type: 'plan'
								id: unit.get 'id'
								name: unit.get 'name'
								sections: clientFile.getIn(['plan', 'sections']).map (section) =>

									Imm.fromJS {
										id: section.get 'id'
										name: section.get 'name'
										targets: section.get('targetIds').map (targetId) =>											
											target = planTargetsById.get targetId
											lastRev = target.last()

											return Imm.fromJS {
												id: lastRev.get 'id'
												name: lastRev.get 'name'
												notes: ''
												metrics: lastRev.get('metricIds').map (metricId) =>
													metric = metricsById.get metricId

													return Imm.fromJS {
														id: metric.get 'id'
														name: metric.get 'name'
														definition: metric.get 'definition'
														value: ''
													}
											}
									}
							}
			}	

	NewProgNotePageUi = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				progNote: @props.progNote

				progEvents: Imm.List()
				editingWhichEvent: null
				selectedEventRelation: null

				success: false
				showExitAlert: false				
			}

		suggestClose: ->
			if @hasChanges() and not @state.showExitAlert
				@setState {showExitAlert: true}
				Bootbox.dialog {
					message: "Are you sure you want to cancel this #{Term('progress note')}?"
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
								@props.closeWindow()
						}
					}
				}
			else
				@props.closeWindow()

		hasChanges: ->
			unless Imm.is @props.progNote, @state.progNote
				return true
			return false
		
		componentWillReceiveProps: (newProps) ->
			unless Imm.is(newProps.progNote, @props.progNote)
				@setState {progNote: newProps.progNote}

		componentDidUpdate: ->
			if @state.editingWhichEvent?
				$('#saveNoteButton').tooltip {
					html: true
					placement: 'top'
					title: "Please finish editing your #{Term 'event'} before saving"
				}
			else
				$('#saveNoteButton').tooltip 'destroy'

		render: ->
			if @props.isLoading
				return R.div({className: 'newProgNotePage'},
					Spinner({
						isOverlay: true
					})
				)

			if @props.loadErrorType?
				return R.div({className: 'newProgNotePage'},
					R.div({className: 'loadError'},
						(switch @props.loadErrorType
							when 'io-error'
								"""
									An error occurred while loading this client's information.
									Please check your network connection and try again.
								"""
							else
								throw new Error """
									Unknown loadErrorType: #{JSON.stringify @props.loadErrorType}
								"""
						)
						R.div({},
							R.button({
								className: 'btn btn-danger'
								onClick: =>
									@props.closeWindow()
							}, "Close")
						)
					)
				)

			clientName = renderName @props.clientFile.get('clientName')
			@props.setWindowTitle "#{clientName}: #{Term 'Progress Note'} - KoNote"

			return R.div({className: 'newProgNotePage'},				
				R.div({className: 'progNote'},

					R.div({clssName: 'backdate'},
						BackdateWidget({onChange: @_updateBackdate})
						if @state.progNote.get('backdate')
							R.span({}, "(back-dated entry)")
					)

					R.hr({})
					R.div({
						className: [
							'units'
							'eventRelationMode' if @state.selectedEventRelation?
						].join ' '
					},
						(@state.progNote.get('units').map (unit) =>
							unitId = unit.get 'id'

							console.info "unitId", unitId

							switch unit.get('type')
								when 'basic'
									R.div({
										className: 'unit basic'
										key: unitId
									},
										R.h1({className: 'name'}, unit.get 'name')
										ExpandingTextArea({
											value: unit.get('notes')
											onFocus: @_selectBasicUnit.bind null, unit
											onChange: @_updateBasicNotes.bind null, unitId
										})
										R.div({className: 'metrics'},
											(unit.get('metrics').map (metric) =>
												metricId = metric.get 'id'

												MetricWidget({
													key: metric.get('id')
													name: metric.get('name')
													definition: metric.get('definition')
													onFocus: @_selectBasicUnit.bind null, unit
													onChange: @_updateBasicMetric.bind(
														null,
														unitId, metricId
													)
													value: metric.get('value')
												})
											).toJS()...
										)
										R.div({
											className: 'events'
											onClick: @_newEventTab.bind null, {unitId}
										},
											
										)
									)
								when 'plan'
									R.div({
										className: 'unit plan'
										key: unitId
									},
										R.h1({}, unit.get 'name')
										R.div({className: "empty #{showWhen unit.get('sections').size is 0}"},
											"This is empty because 
											the client has no #{Term 'plan'} #{Term 'sections'}."
										)
										(unit.get('sections').map (section) =>
											sectionId = section.get 'id'

											R.section({key: sectionId},
												R.h2({}, section.get 'name')

												(section.get('targets').map (target) =>														
													targetId = target.get 'id'

													R.div({
														className: [
															'target'
															'selectedEventRelation' if Imm.is target, @state.selectedEventRelation
														].join ' '
														key: targetId
														onClick: @_selectEventRelation.bind(null, target) if @state.selectedEventRelation?
													},
														R.h3({}, target.get 'name')
														ExpandingTextArea {
															value: target.get 'notes'
															onFocus: @_selectPlanTarget.bind(
																null, unit, section, target
															)
															onChange: @_updatePlanTargetNotes.bind(
																null, unitId, sectionId, targetId
															)
														}
														R.div({className: 'metrics'},
															(target.get('metrics').map (metric) =>
																metricId = metric.get 'id'

																MetricWidget {
																	key: metricId
																	name: metric.get 'name'
																	definition: metric.get 'definition'
																	value: metric.get 'value'
																	onFocus: @_selectPlanTarget.bind(
																		null,
																		unit, section, target
																	)
																	onChange: @_updatePlanTargetMetric.bind(
																		null,
																		unitId, sectionId, targetId, metricId
																	)
																}
															)
														)	
													)
												).toJS()...
											)
										).toJS()...
									)
						).toJS()...
					)
					R.div({className: 'buttonRow'},
						R.button({
							className: "save btn btn-primary #{'disabled' if @state.editingWhichEvent? or
								not @hasChanges()}"
							id: 'saveNoteButton'
							onClick: @_save unless @state.editingWhichEvent? or not @hasChanges()
						},
							FaIcon 'check'
							'Save'
						)
					)
				)
				ProgNoteDetailView({
					item: @state.selectedItem
					progNoteHistories: @props.progNoteHistories
					progEvents: @props.progEvents
				})
				R.div({className: 'eventsPanel'},
					R.span({className: 'title'}, Term "Events")
					R.div({
						className: [
							'eventsList'
							'editMode' if @state.editingWhichEvent?
						].join ' '
					},						
						(@state.progEvents.map (thisEvent, index) =>
							isBeingEdited = @state.editingWhichEvent is index

							R.div({								
								className: [
										'eventTab'
										'isEditing' if isBeingEdited
								].join ' '
								key: index
							}, 
								R.div({
									className: 'icon'
									onClick: @_editEventTab.bind(null, index) if not @state.editingWhichEvent?
								},
									FaIcon 'calendar'
								)
								EventTabView({
									data: thisEvent
									atIndex: index
									progNote: @state.progNote
									save: @_saveEventData
									cancel: @_cancelEditing
									editMode: @state.editingWhichEvent?
									isBeingEdited
									selectedEventRelation: @state.selectedEventRelation
									selectEventRelation: @_selectEventRelation
								})
							)
						)
						R.button({							
							className: 'btn btn-default addEventButton'
							onClick: @_newEventTab
							disabled: @state.editingWhichEvent?
						}, FaIcon('plus'))
					)
				)
			)

		_newEventTab: (relatedId) ->			
			newProgEvent = if relatedId? then {relatedId} else {}
			# Add in the new event, select last one
			@setState {progEvents: @state.progEvents.push newProgEvent}, => 
				@setState {editingWhichEvent: @state.progEvents.size - 1}

		_editEventTab: (index) ->
			@setState {editingWhichEvent: index}

		_saveEventData: (data, index) ->
			newProgEvents = @state.progEvents.set index, data
			@setState {progEvents: newProgEvents}, @_cancelEditing
			
		_cancelEditing: (index) ->
			# Delete if new event
			if _.isEmpty @state.progEvents.get(index)
				@setState {progEvents: @state.progEvents.delete(index)}

			@setState {editingWhichEvent: null}

		_selectEventRelation: (selectedEventRelation) ->
			console.log "Selecting eventRelation", selectedEventRelation
			@setState {selectedEventRelation}

			
		_getUnitIndex: (unitId) ->
			result = @state.progNote.get('units')
			.findIndex (unit) =>
				return unit.get('id') is unitId

			if result is -1
				throw new Error "could not find unit with ID #{JSON.stringify unitId}"

			return result

		_getPlanSectionIndex: (unitIndex, sectionId) ->
			console.info unitIndex, sectionId

			result = @state.progNote.getIn(['units', unitIndex, 'sections'])
			.findIndex (section) =>
				return section.get('id') is sectionId

			if result is -1
				throw new Error "could not find unit with ID #{JSON.stringify sectionId}"

			return result

		_getPlanTargetIndex: (unitIndex, sectionIndex, targetId) ->
			result = @state.progNote.getIn(['units', unitIndex, 'sections', sectionIndex, 'targets'])
			.findIndex (target) =>
				return target.get('id') is targetId

			if result is -1
				throw new Error "could not find target with ID #{JSON.stringify targetId}"

			return result


		_selectBasicUnit: (unit) ->
			@setState {
				selectedItem: Imm.fromJS {
					type: 'basicUnit'
					unitId: unit.get 'id'
					unitName: unit.get 'name'
				}
			}

		_selectPlanTarget: (unit, section, target) ->
			@setState {
				selectedItem: Imm.fromJS {
					type: 'planSectionTarget'
					unitId: unit.get 'id'
					unitName: unit.get 'name'
					sectionId: section.get 'id'
					sectionName: section.get 'name'
					targetId: target.get 'id'
					targetName: target.get 'name'
				}
			}

		_updateBackdate: (event) ->
			newBackdate = Moment(event.date).format(Persist.TimestampFormat)
			if Moment(event.date).format('YYYY-MM-DD-HH') is Moment().format('YYYY-MM-DD-HH')
				@setState {progNote: @state.progNote.setIn ['backdate'], ''}
			else
				@setState {progNote: @state.progNote.setIn ['backdate'], newBackdate}

		_updateBasicNotes: (unitId, event) ->
			newNotes = event.target.value

			unitIndex = @_getUnitIndex unitId
			progNote = @state.progNote.setIn ['units', unitIndex, 'notes'], event.target.value

			@setState {
				progNote: @state.progNote.setIn(
					[
						'units', unitIndex
						'notes'
					]
					newNotes
				)
			}

		_updateBasicMetric: (unitId, metricId, newMetricValue) ->
			return unless @_isValidMetric(newMetricValue)

			unitIndex = @_getUnitIndex unitId

			metricIndex = @state.progNote.getIn(['units', unitIndex, 'metrics'])
			.findIndex (metric) =>
				return metric.get('id') is metricId

			@setState {
				progNote: @state.progNote.setIn(
					[
						'units', unitIndex
						'metrics', metricIndex
						'value'
					]
					newMetricValue
				)
			}

		_updatePlanTargetNotes: (unitId, sectionId, targetId, event) ->
			newNotes = event.target.value

			unitIndex = @_getUnitIndex unitId
			sectionIndex = @_getPlanSectionIndex unitIndex, sectionId
			targetIndex = @_getPlanTargetIndex unitIndex, sectionIndex, targetId

			@setState {
				progNote: @state.progNote.setIn(
					[
						'units', unitIndex
						'sections', sectionIndex
						'targets', targetIndex
						'notes'
					]
					newNotes
				)
			}

		_updatePlanTargetMetric: (unitId, sectionId, targetId, metricId, newMetricValue) ->
			return unless @_isValidMetric(newMetricValue)

			unitIndex = @_getUnitIndex unitId
			sectionIndex = @_getPlanSectionIndex unitIndex, sectionId
			targetIndex = @_getPlanTargetIndex unitIndex, sectionIndex, targetId

			metricIndex = @state.progNote.getIn(
				['units', unitIndex, 'sections', sectionIndex, 'targets', targetIndex, 'metrics']
			).findIndex (metric) =>
				return metric.get('id') is metricId			

			@setState {
				progNote: @state.progNote.setIn(
					[
						'units', unitIndex
						'sections', sectionIndex
						'targets', targetIndex
						'metrics', metricIndex
						'value'
					]
					newMetricValue
				)
			}

		_isValidMetric: (value) -> value.match /^-?\d*\.?\d*$/

		_save: ->
			progNoteId = null

			Async.series [
				(cb) =>
					ActiveSession.persist.progNotes.create @state.progNote, (err, obj) =>
						if err
							cb err
							return

						progNoteId = obj.get('id')
						cb()
				(cb) =>
					Async.each @state.progEvents.toArray(), (progEvent, cb) =>		
						# Tack on the new progress note ID to all created events					
						progEvent = Imm.fromJS(progEvent)
						.set('relatedProgNoteId', progNoteId)
						.set('clientFileId', clientFileId)

						ActiveSession.persist.progEvents.create progEvent, cb

					, (err) =>
						if err
							cb err
							return

						cb()
			], (err) =>
				if err
					if err instanceof Persist.IOError
						Bootbox.alert """
							An error occurred while saving your work.  
							Please check your network connection and try again.
						"""
						return

					CrashHandler.handle err
					return
				@props.closeWindow()


	BackdateWidget = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]
		componentDidMount: ->
			$(@refs.backdate.getDOMNode()).datetimepicker({
				format: 'MMM-DD-YYYY h:mm A'
				defaultDate: Moment()
				maxDate: Moment()
				widgetPositioning: {
					vertical: 'bottom'
				}
			}).on 'dp.change', (e) =>
				@props.onChange e
		render: ->
			return R.div({className: 'input-group'},
				R.input({
					ref: 'backdate'
					className: 'form-control backdate date'
				},
					R.span({className: 'input-group-addon'}
						FaIcon('calendar')
					)
				)
			)


	return NewProgNotePage

module.exports = {load}
