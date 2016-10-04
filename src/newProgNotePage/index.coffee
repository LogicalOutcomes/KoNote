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
	{PropTypes} = React
	R = React.DOM

	Gui = win.require 'nw.gui'
	Window = Gui.Window.get(win)

	EventTabView = require('./eventTabView').load(win)
	CrashHandler = require('../crashHandler').load(win)
	ExpandingTextArea = require('../expandingTextArea').load(win)
	MetricWidget = require('../metricWidget').load(win)
	ProgNoteDetailView = require('../progNoteDetailView').load(win)
	Dialog = require('../dialog').load(win)
	LayeredComponentMixin = require('../layeredComponentMixin').load(win)
	Spinner = require('../spinner').load(win)

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

				isEventPlanRelationMode: null
				selectedEventPlanRelation: null
				hoveredEventPlanRelation: null
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
			originalProgNote = @state.progNote
			progNote = @_compileProgNoteData(@state.progNote)

			hasProgNotes = not Imm.is originalProgNote, progNote
			hasProgEvents = not @state.progEvents.isEmpty()

			return hasProgNotes or hasProgEvents

		componentWillReceiveProps: (newProps) ->
			unless Imm.is(newProps.progNote, @props.progNote)
				@setState {progNote: newProps.progNote}

		componentWillMount: ->
			clientName = renderName @props.clientFile.get('clientName')

			@props.setWindowTitle """
				#{Config.productName} (#{global.ActiveSession.userName}) - #{clientName}: New #{Term 'Progress Note'}
			"""

		componentDidMount: ->
			global.ActiveSession.persist.eventBus.trigger 'newProgNotePage:loaded'
			Window.focus()

			# Store beginTimestamp as class var, since it wont change
			@beginTimestamp = Moment().format(Persist.TimestampFormat)

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


			return R.div({className: 'newProgNotePage animated fadeIn'},

				R.div({className: 'progNote'},
					R.div({className: 'backdateContainer'},
						BackdateWidget({
							onChange: @_updateBackdate
							message: @state.progNote.get('backdate') or false
						})
					)

					R.div({className: 'units'},
						(@state.progNote.get('units').map (unit) =>
							unitId = unit.get 'id'
							unitType = unit.get 'type'

							(switch unitType
								when 'basic'
									Entry({
										ref: unitId
										key: unitId
										className: 'unit basic'
										unit
										entryData: unit
										selectItem: @_selectItem
									})
								when 'plan'
									PlanUnit({
										ref: unitId
										key: unitId
										unit
										selectItem: @_selectItem
									})
								else
									throw new Error """
										Invalid progNote unit type: #{unitType} for progNote #{@state.progNote.toJS()}
									"""
							)
						)

						# PROTOTYPE Shift Summary Feature
						Entry({
							ref: 'shiftSummary'
							className: "shiftSummary unit basic #{showWhen Config.features.shiftSummaries.isEnabled}"
							entryData: Imm.Map {name: "Shift Summary"}
							# selectItem: @_selectItem # TODO: Shift summary history
						})
					)

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
						(@state.progEvents.map (thisEvent, index) =>
							isBeingEdited = @state.editingWhichEvent is index
							isGlobalEvent = !!thisEvent.get('globalEvent')

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
									FaIcon (if isGlobalEvent then 'globe' else 'calendar')
								)
								EventTabView({
									data: thisEvent
									clientFileId: @props.clientFile.get('id')
									backdate: @state.progNote.get('backdate')
									eventTypes: @props.eventTypes
									atIndex: index
									progNote: @state.progNote
									saveProgEvent: @_saveProgEvent
									cancel: @_cancelEditing
									editMode: @state.editingWhichEvent?
									clientPrograms: @props.clientPrograms
									isBeingEdited

									updateEventPlanRelationMode: @_updateEventPlanRelationMode
									selectedEventPlanRelation: @state.selectedEventPlanRelation
									selectEventPlanRelation: @_selectEventPlanRelation
									hoverEventPlanRelation: @_hoverEventPlanRelation
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
			newProgEvent = Imm.Map()
			# Add in the new event, select last one
			@setState {progEvents: @state.progEvents.push newProgEvent}, =>
				@setState {editingWhichEvent: @state.progEvents.size - 1}

		_editEventTab: (index) ->
			@setState {editingWhichEvent: index}

		_saveProgEvent: (data, index) ->
			newProgEvents = @state.progEvents.set index, data
			@setState {progEvents: newProgEvents}, @_cancelEditing

		_cancelEditing: (index) ->
			# Delete if new event
			if @state.progEvents.get(index) and @state.progEvents.get(index).isEmpty()
				@setState {progEvents: @state.progEvents.delete(index)}

			@setState {
				selectedEventPlanRelation: null
				hoveredEventPlanRelation: null
				editingWhichEvent: null
			}

		_compileProgNoteData: (progNote) ->
			# Extract data from all unit refs, plus notes from shiftSummary
			progNoteWithUnits = getDataFromRefs @refs, progNote, 'units'
			shiftSummaryNotes = @refs.shiftSummary.getData().get('notes')

			return progNoteWithUnits.set 'summary', shiftSummaryNotes

		_selectItem: (unit, section, target) ->
			if section and target
				@_selectPlanTarget unit, section, target
			else
				@_selectBasicUnit unit

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

		_updateBackdate: (event) ->
			if event
				newBackdate = Moment(event.date).format(Persist.TimestampFormat)
				@setState {progNote: @state.progNote.set 'backdate', newBackdate}
			else
				@setState {progNote: @state.progNote.set 'backdate', ''}

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

		_save: ->
			if not @hasChanges()
				Bootbox.alert """
					Sorry, a #{Term 'progress note'} must contain at least 1 note or #{Term 'event'}.
				"""
				return

			authorProgramId = global.ActiveSession.programId or ''

			# Fetch notes data, add final properties for save
			progNote = @_compileProgNoteData(@state.progNote)
			.set 'authorProgramId', authorProgramId
			.set 'beginTimestamp', @beginTimestamp

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
								.remove('relatedElement')

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
				if @props.message
					R.span({
						className: 'text-danger btn'
						onClick: =>
							$(@refs.backdate).val(Moment().format('MMM-DD-YYYY h:mm A'))
							@props.onChange null
						title: 'Remove Backdate'
					},
						'Backdated '
						FaIcon('times')
					)
			)


	PlanUnit =  React.createFactory React.createClass
		displayName: 'PlanUnit'

		getData: -> getDataFromRefs(@refs, @props.unit, 'sections')

		render: ->
			{unit, selectItem} = @props

			return R.div({className: 'unit plan'},
				(unit.get('sections').map (section) =>
					PlanSection({
						ref: section.get 'id'
						key: section.get 'id'
						unit
						section
						selectItem
					})
				)
			)


	PlanSection = React.createFactory React.createClass
		displayName: 'PlanSection'
		mixins: [React.addons.PureRenderMixin]

		getData: -> getDataFromRefs(@refs, @props.section, 'targets')

		render: ->
			{unit, section, selectItem} = @props

			return R.section({onClick: @getData},
				R.h2({}, section.get 'name')

				(section.get('targets').map (target) =>
					targetId = target.get 'id'

					Entry({
						ref: targetId
						key: targetId
						className: 'target'
						unit
						parentData: section
						entryData: target
						selectItem
					})
				)
			)


	# Generic 'entry' component, which can be either a planTarget or a basicUnit
	Entry = React.createFactory React.createClass
		displayName: 'Entry'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			state = {notes: ''}

			# Load metrics into state if exists
			if @props.entryData.get('metrics')?
				state.metrics = @props.entryData.get('metrics')

			return state

		propTypes: {
			# className: PropTypes.string.isRequired()
			# selectItem: PropTypes.func.isRequired()

			# unit: ImmPropTypes.map.isRequired()
			# parentData: ImmPropTypes.map # (section or undefined)
			# entryData: ImmPropTypes.map.isRequired() # (target or unit)
		}

		getDefaultProps: -> {
			className: ''
			entryData: Imm.Map()
			selectItem: (->)
		}

		getData: -> @props.entryData.merge @state

		render: ->
			{unit, parentData, entryData, selectItem, className} = @props

			return R.div({className: "entry #{className}"},
				R.h3({},
					entryData.get 'name'

					R.span({
						className: 'star'
						title: "Mark as Important"
						onClick: @_starEntry
					},
						(if @state.notes.includes "***"
							FaIcon('star', {className: 'checked'})
						else
							FaIcon('star-o')
						)
					)
				)

				ExpandingTextArea({
					ref: 'textarea'
					value: @state.notes
					onFocus: selectItem.bind null, unit, parentData, entryData
					onChange: @_updateNotes
				})

				MetricsView({
					ref: 'metrics'
					unit
					parentData
					entryData
					metrics: @state.metrics
					updateMetric: @_updateMetric
					selectItem
				})
			)

		_updateNotes: (event) ->
			notes = event.target.value
			@setState {notes}

		_updateMetric: (index, value) ->
			# Validate is valid metric (+/- integer)
			return unless value.match /^-?\d*\.?\d*$/

			metrics = @state.metrics.setIn [index, 'value'], value
			@setState {metrics}

		_starEntry: ->
			notes = if @state.notes.includes "***"
				@state.notes.replace(/\*\*\*/g, '')
			else
				"***" + @state.notes

			@setState {notes}, =>
				@refs.textarea.focus()


	MetricsView = React.createFactory React.createClass
		displayName: 'MetricsView'
		mixins: [React.addons.PureRenderMixin]

		render: ->
			{metrics, unit, parentData, entryData, selectItem, updateMetric} = @props

			return null if not metrics or metrics.isEmpty()

			return R.div({className: 'metrics'},
				(metrics.map (metric, index) =>
					metricId = metric.get 'id'

					MetricWidget {
						key: metricId
						name: metric.get 'name'
						definition: metric.get 'definition'
						value: metrics.getIn [index, 'value']
						onFocus: selectItem.bind null, unit, parentData, entryData
						onChange: updateMetric.bind null, index
						isEditable: true
					}
				)
			)


	# Utility for mapping over each component's getData() method,
	# and returning the progNote data with current note/metric values intact
	getDataFromRefs = (refs, data, name) ->
		ids = data.get(name).map (child) -> child.get('id')
		values = ids.map (id) => refs[id].getData()
		return data.set name, values


	return NewProgNotePage

module.exports = {load}
