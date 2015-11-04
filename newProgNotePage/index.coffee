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

	myTemplate = Imm.fromJS Config.templates[Config.useTemplate]

	NewProgNotePage = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				isLoading: true
				loadErrorType: null
				progNote: null
				clientFile: null
				progNotes: null
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
				progNotes: @state.progNotes
				progEvents: @state.progEvents

				closeWindow: @props.closeWindow
				setWindowTitle: @props.setWindowTitle
			})

		_loadData: ->
			template = myTemplate # TODO
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
					Async.map progNoteHeaders.toArray(), (progNoteHeader, cb) =>
						ActiveSession.persist.progNotes.read clientFileId, progNoteHeader.get('id'), cb
					, (err, results) =>
						if err
							cb err
							return

						@setState (state) =>
							return {progNotes: Imm.List(results)}

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

				# Done loading data, we can generate the prognote now
				@setState {						
						isLoading: false
						progNote
					}

		_createProgNoteFromTemplate: (template, clientFile, planTargetsById, metricsById) ->
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

	NewProgNotePageUi = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				progNote: @props.progNote

				progEvents: Imm.List()
				editingWhichEvent: null
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
											"This #{Term 'section'} is empty because the client has no #{Term 'plan'} #{Term 'targets'}."
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
					progNotes: @props.progNotes
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
									save: @_saveEventData
									cancel: @_cancelEditing
									editMode: @state.editingWhichEvent?
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
			# Add in the new event, select last one
			@setState {progEvents: @state.progEvents.push {}}, => 
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
			return @render() if @_invalidMetricFormat(newValue)

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
			return @render() if @_invalidMetricFormat(newValue)

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
		_invalidMetricFormat: (value) -> not value.match /^-?\d*\.?\d*$/
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


	return NewProgNotePage

module.exports = {load}
