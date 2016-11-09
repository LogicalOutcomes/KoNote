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

	Window = nw.Window.get(win)

	EventTabView = require('./eventTabView').load(win)
	CrashHandler = require('../crashHandler').load(win)
	ExpandingTextArea = require('../expandingTextArea').load(win)
	MetricWidget = require('../metricWidget').load(win)
	WithTooltip = require('../withTooltip').load(win)
	ProgNoteDetailView = require('../progNoteDetailView').load(win)

	{FaIcon, renderName, showWhen, stripMetadata,
	getUnitIndex, getPlanSectionIndex, getPlanTargetIndex} = require('../utils').load(win)

	progNoteTemplate = Imm.fromJS Config.templates[Config.useTemplate]


	NewProgNotePage = React.createFactory React.createClass
		displayName: 'NewProgNotePage'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				status: 'init'

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
			unless @state.status is 'ready' then return R.div({})

			NewProgNotePageUi({
				ref: 'ui'
				status: @state.status

				loadErrorType: @state.loadErrorType
				progNote: @state.progNote
				clientFile: @state.clientFile
				progNoteHistories: @state.progNoteHistories
				progEvents: @state.progEvents
				eventTypes: @state.eventTypes
				programsById: @state.programsById
				clientPrograms: @state.clientPrograms

				closeWindow: @props.closeWindow
				setWindowTitle: @props.setWindowTitle
			})

		_loadData: ->
			template = progNoteTemplate

			# This is attached to global by clientFile
			{
				clientFile
				planTargetsById
				metricsById
				progNoteHistories
				progEvents
				eventTypes
				programsById
				clientPrograms
			} = global.dataStore[clientFileId]

			# Build progNote with template
			progNote = @_createProgNoteFromTemplate(
				template
				clientFile
				planTargetsById
				metricsById
			)

			# Done loading data, we can load in the empty progNote object
			@setState {
				status: 'ready'
				clientFile
				progNote

				planTargetsById
				metricsById
				programsById
				progNoteHistories
				progEvents
				eventTypes
				clientPrograms
			}, ->
				# We're done with this dataStore, so delete it to preserve memory
				delete global.dataStore[clientFileId]

		_createProgNoteFromTemplate: (template, clientFile, planTargetsById, metricsById) ->
			return Imm.fromJS {
				type: 'full'
				status: 'default'
				clientFileId: clientFile.get('id')
				templateId: template.get('id')
				backdate: ''
				summary: ''
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
								sections: clientFile.getIn(['plan', 'sections'])
								.filter (section) => section.get('status') is 'default'
								.map (section) =>

									Imm.fromJS {
										id: section.get 'id'
										name: section.get 'name'
										targets: section.get 'targetIds'
										.filter (targetId) =>
											target = planTargetsById.get targetId
											return target.get('status') is 'default'
										.map (targetId) =>
											target = planTargetsById.get targetId

											return Imm.fromJS {
												id: target.get 'id'
												name: target.get 'name'
												description: target.get 'description'
												notes: ''
												metrics: target.get('metricIds').map (metricId) =>
													metric = metricsById.get metricId

													return Imm.fromJS {
														id: metric.get 'id'
														name: metric.get 'name'
														definition: metric.get 'definition'
														value: ''
													}
											}
									}
								.filter (section) => not section.get('targets').isEmpty()
							}
			}

	NewProgNotePageUi = React.createFactory React.createClass
		displayName: 'NewProgNotePageUi'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				progNote: @props.progNote

				progEvents: Imm.List()
				editingWhichEvent: null
			}

		suggestClose: ->
			if @hasChanges()
				Bootbox.dialog {
					message: "Are you sure you want to cancel this #{Term('progress note')}?"
					buttons: {
						cancel: {
							label: "No"
							className: 'btn-default'
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
			# Ignore backdate from comparison, it doesn't count
			progNoteTemplate = @props.progNote.remove('backdate')
			progNote = @state.progNote.remove('backdate')

			hasProgNotes = not Imm.is progNoteTemplate, progNote
			hasProgEvents = not @state.progEvents.isEmpty()

			return hasProgNotes or hasProgEvents

		componentWillReceiveProps: (newProps) ->
			unless Imm.is(newProps.progNote, @props.progNote)
				@setState {progNote: newProps.progNote}

		componentDidMount: ->
			global.ActiveSession.persist.eventBus.trigger 'newProgNotePage:loaded'
			Window.focus()

			# Store beginTimestamp as static class variable, since it wont change
			@beginTimestamp = Moment().format(Persist.TimestampFormat)

		render: ->

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
								onClick: @props.closeWindow
							}, "Close")
						)
					)
				)


			isBackDated = !!@state.progNote.get('backdate')


			return R.div({className: 'newProgNotePage animated fadeIn'},

				R.div({className: 'progNote'},
					R.div({className: 'backdateContainer'},
						BackdateWidget({
							onChange: @_updateBackdate
							isBackdated
						})
					)

					R.div({className: 'units'},
						(@state.progNote.get('units').map (unit) =>
							unitId = unit.get 'id'

							switch unit.get('type')
								when 'basic'
									R.div({
										key: unitId
										className: 'unit basic'
									},
										R.h1({className: 'unitName'}, unit.get 'name')
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
													isEditable: true
												})
											).toJS()...
										)
									)
								when 'plan'
									R.div({
										className: 'unit plan'
										key: unitId
									},
										(unit.get('sections').map (section) =>
											sectionId = section.get 'id'

											R.section({key: sectionId},
												R.h2({}, section.get 'name')

												(section.get('targets').map (target) =>
													targetId = target.get 'id'

													R.div({
														key: targetId
														className: 'target'
													},
														R.h3({},
															target.get 'name'
															R.span({
																className: 'star'
																title: "Mark as Important"
																onClick: @_starTarget.bind(
																	null, unitId, sectionId, targetId, target.get 'notes'
																)
															},
																if target.get('notes').includes "***"
																	FaIcon('star', {className:'checked'})
																else
																	FaIcon('star-o')
															)
														)
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
																	isEditable: true
																}
															)
														)
													)
												).toJS()...
											)
										).toJS()...
									)
						).toJS()...

						# PROTOTYPE Shift Summary Feature
						(if Config.features.shiftSummaries.isEnabled
							R.div({
								id: 'shiftSummaryField'
								className: 'unit basic'
							},
								R.h2({}, "Shift Summary")
								ExpandingTextArea({
									value: @state.progNote.get('summary')
									onChange: @_updateSummary
								})
							)
						)
					)

					(if @hasChanges()
						WithTooltip({
							title: if @state.editingWhichEvent?
								"Please finish editing your #{Term 'event'} before saving"
							placement: 'top'
						},
							R.button({
								id: 'saveNoteButton'
								className: 'btn btn-success btn-lg animated fadeInUp'
								disabled: @state.editingWhichEvent?
								onClick: @_save
							},
								"Save "
								FaIcon('check')
							)
						)
					)
				)

				ProgNoteDetailView({
					item: @state.selectedItem
					progNoteHistories: @props.progNoteHistories
					progEvents: @props.progEvents
					eventTypes: @props.eventTypes
					programsById: @props.programsById
				})

				R.div({className: 'eventsPanel'},
					R.span({className: 'title'}, Term "Events")
					R.div({
						className: [
							'eventsList'
							'editMode' if @state.editingWhichEvent?
						].join ' '
					},
						(@state.progEvents.map (progEvent, index) =>
							isBeingEdited = @state.editingWhichEvent is index
							isGlobalEvent = progEvent.has 'globalEvent'

							R.div({
								key: index
								className: [
									'eventTab'
									'isEditing' if isBeingEdited
								].join ' '
							},
								R.div({
									className: 'icon'
									onClick: @_editEventTab.bind(null, index) if not @state.editingWhichEvent?
								},
									FaIcon (if isGlobalEvent then 'globe' else 'calendar')
								)
								EventTabView({
									progEvent
									clientFileId: @props.clientFile.get('id')
									backdate: @state.progNote.get('backdate')
									eventTypes: @props.eventTypes
									saveProgEvent: @_saveProgEvent.bind null, index
									cancel: @_cancelEditing.bind null, index
									editMode: @state.editingWhichEvent?
									clientPrograms: @props.clientPrograms
									isBeingEdited
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

		_newEventTab: ->
			# Add in the new (empty) progEvent
			progEvent = Imm.Map()
			progEvents = @state.progEvents.push progEvent

			# Select last one for editing
			editingWhichEvent = progEvents.size - 1

			@setState {progEvents, editingWhichEvent}

		_editEventTab: (index) ->
			editingWhichEvent = index
			@setState {editingWhichEvent}

		_saveProgEvent: (index, progEvent) ->
			progEvents = @state.progEvents.set index, progEvent
			editingWhichEvent = null

			@setState {progEvents, editingWhichEvent}

		_cancelEditing: (index) ->
			# Delete if new event
			editingWhichEvent = null
			progEvents = @state.progEvents

			if @state.progEvents.has(index) and @state.progEvents.get(index).isEmpty()
				progEvents = progEvents.delete index

			@setState {progEvents, editingWhichEvent}

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
					targetDescription: target.get 'description'
				}
			}

		_starTarget: (unitId, sectionId, targetId, note) ->
			if note.includes "***"
				newNotes = note.replace(/\*\*\*/g, '')
			else
				newNotes = "***" + note

			unitIndex = getUnitIndex @state.progNote, unitId
			sectionIndex = getPlanSectionIndex @state.progNote, unitIndex, sectionId
			targetIndex = getPlanTargetIndex @state.progNote, unitIndex, sectionIndex, targetId

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

		_updateBackdate: (event) ->
			backdate = if event then event.date.format(Persist.TimestampFormat) else ''
			progNote = @state.progNote.set 'backdate', backdate

			@setState {progNote}

		_updateBasicNotes: (unitId, event) ->
			newNotes = event.target.value

			unitIndex = getUnitIndex @state.progNote, unitId
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

			unitIndex = getUnitIndex @state.progNote, unitId

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

			unitIndex = getUnitIndex @state.progNote, unitId
			sectionIndex = getPlanSectionIndex @state.progNote, unitIndex, sectionId
			targetIndex = getPlanTargetIndex @state.progNote, unitIndex, sectionIndex, targetId

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

			unitIndex = getUnitIndex @state.progNote, unitId
			sectionIndex = getPlanSectionIndex @state.progNote, unitIndex, sectionId
			targetIndex = getPlanTargetIndex @state.progNote, unitIndex, sectionIndex, targetId

			metricIndex = @state.progNote.getIn(
				[
					'units', unitIndex
					'sections', sectionIndex
					'targets', targetIndex,
					'metrics'
				]
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

		_updateSummary: (event) ->
			summary = event.target.value
			progNote = @state.progNote.set 'summary', summary

			@setState {progNote}

		_isValidMetric: (value) -> value.match /^-?\d*\.?\d*$/

		_save: ->
			authorProgramId = global.ActiveSession.programId or ''
			progNote = @state.progNote
			.set('authorProgramId', authorProgramId)
			.set('beginTimestamp', @beginTimestamp)

			progNoteId = null
			createdProgNote = null

			Async.series [
				(cb) =>
					ActiveSession.persist.progNotes.create progNote, (err, result) =>
						if err
							cb err
							return

						createdProgNote = result
						progNoteId = createdProgNote.get('id')
						cb()

				(cb) =>
					Async.each @state.progEvents.toArray(), (progEvent, cb) =>
						# Tack on contextual information about progNote & client
						progEvent = Imm.fromJS(progEvent)
						.set('relatedProgNoteId', progNoteId)
						.set('clientFileId', clientFileId)
						.set('authorProgramId', authorProgramId)
						.set('backdate', createdProgNote.get('backdate'))
						.set('status', 'default')

						globalEvent = progEvent.get('globalEvent')

						if globalEvent
							progEvent = progEvent.remove('globalEvent')

						progEventId = null

						Async.series [
							(cb) =>
								ActiveSession.persist.progEvents.create progEvent, (err, result) ->
									if err
										cb err
										return

									progEventId = result.get('id')
									cb()

							(cb) =>
								if not globalEvent
									cb()
									return

								programId = globalEvent.get('programId')

								# Tack on contextual information about the original progEvent
								globalEvent = globalEvent
								.set('relatedProgEventId', progEventId)
								.set('relatedProgNoteId', createdProgNote.get('id'))
								.set('programId', programId)
								.set('backdate', createdProgNote.get('backdate'))
								.set('status', 'default')

								ActiveSession.persist.globalEvents.create globalEvent, cb

						], cb

					, cb

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
		displayName: 'BackdateWidget'
		mixins: [React.addons.PureRenderMixin]

		componentDidMount: ->
			$(@refs.backdate).datetimepicker({
				format: 'MMM-DD-YYYY h:mm A'
				defaultDate: Moment()
				maxDate: Moment()
				sideBySide: true
				showClose: true
				toolbarPlacement: 'bottom'
				widgetPositioning: {
					vertical: 'bottom'
				}
			}).on 'dp.change', @props.onChange

		render: ->
			return R.div({className: 'input-group'},
				R.input({
					ref: 'backdate'
					className: 'backdate date btn btn-default'
				})

				(if @props.isBackdated
					R.span({
						className: 'text-danger btn'
						onClick: =>
							$(@refs.backdate).val(Moment().format('MMM-DD-YYYY h:mm A'))
							@props.onChange('')
						title: 'Remove Backdate'
					},
						'Backdated '
						FaIcon('times')
					)
				)
			)

	return NewProgNotePage

module.exports = {load}
