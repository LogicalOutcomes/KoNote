# UI logic for the progress note creation window
#
# TODO New plan: create new prognote object/file, trigger update via event bus

_ = require 'underscore'
Imm = require 'immutable'
Moment = require 'moment'

Config = require '../config'
Persist = require '../persist'

load = (win, {clientId}) ->
	# Libraries from browser context
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM
	Gui = win.require 'nw.gui'
	ExpandingTextArea = require('../expandingTextArea').load(win)
	Spinner = require('../spinner').load(win)
	{FaIcon, renderName, showWhen} = require('../utils').load(win)

	nwWin = Gui.Window.get(win)

	myTemplate = Imm.fromJS {
		id: 'fake-template-lolololol'
		name: 'Fake Template'
		sections: [
			{
				id: 'section1'
				type: 'basic'
				name: 'Subjective'
				metricIds: []
			}
			{
				id: 'section2'
				type: 'basic'
				name: 'Objective'
				metricIds: []
			}
			{
				id: 'section3'
				type: 'basic'
				name: 'Assessment'
				metricIds: []
			}
			{
				id: 'section4'
				type: 'plan'
				name: 'Plan'
			}
		]
	}

	createProgNoteFromTemplate = (template, clientFile, planTargetsById, metricsById) ->
		return Imm.fromJS {
			type: 'full'
			author: 'xxx' # TODO
			clientId: clientFile.get('clientId')
			sections: template.get('sections').map (section) =>
				switch section.get('type')
					when 'basic'
						return Imm.fromJS {
							type: 'basic'
							id: section.get 'id'
							name: section.get 'name'
							notes: ''
							metrics: section.get('metricIds').map (metricId) =>
								# TODO how is this going to be loaded async'ly?
								m = metricsById[metricId]
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

	process.nextTick ->
		React.render new NewProgNotePage(), $('#container')[0]

	NewProgNotePage = React.createFactory React.createClass
		getInitialState: ->
			return {
				clientFile: null
				metricsById: Imm.Map()
				progNote: null
				success: false
			}
		componentDidMount: ->
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

			# Start loading stuff
			Persist.ClientFile.readLatestRevisions clientId, 1, (err, revisions) =>
				if err
					console.error err.stack
					Bootbox.alert "An error occurred while loading the client file"
					return

				clientFile = revisions[0]
				@setState {clientFile}, =>
					Persist.PlanTarget.readClientFileTargets clientFile, (err, planTargetsById) =>
						if err
							cb err
							return

						@setState {planTargetsById}, =>
							@_onDataLoaded()
			# TODO read metrics
		_onDataLoaded: ->
			# TODO check if metrics done

			unless @state.clientFile?
				return

			# Done loading data, we can generate the prognote now
			progNote = createProgNoteFromTemplate(
				myTemplate, @state.clientFile, @state.planTargetsById, @state.metricsById
			)
			@setState {progNote}
		_hasChanges: ->
			# TODO
		render: ->
			unless @state.progNote?
				return R.div({className: 'newProgNotePage'},
					Spinner({isOverlay: true, isVisible: not @state.progNote?})
				)

			clientName = renderName @state.clientFile.get('clientName')
			nwWin.title = "#{clientName}: Progress Note - KoNote"

			return R.div({className: 'newProgNotePage'},
				R.div({className: 'sections'},
					(@state.progNote.get('sections').map (section) =>
						switch section.get('type')
							when 'basic'
								R.div({className: 'basic section', key: section.get('id')},
									R.h1({className: 'name'}, section.get('name'))
									ExpandingTextArea({
										value: section.get('notes')
										onChange: @_updateBasicSectionNotes.bind null, section.get('id')
									})
									# TODO metrics
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
													onChange: @_updatePlanSectionNotes.bind null, section.get('id'), target.get('id')
												})
												# TODO metrics
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
		_getSectionIndex: (sectionId) ->
			return @state.progNote.get('sections').findIndex (s) =>
				return s.get('id') is sectionId
		_updateBasicSectionNotes: (sectionId, event) ->
			sectionIndex = @_getSectionIndex sectionId

			@setState {
				progNote: @state.progNote.setIn ['sections', sectionIndex, 'notes'], event.target.value
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
		_save: ->
			Persist.ProgNote.create @state.progNote, (err) =>
				if err
					console.error err.stack
					Bootbox.alert "An error occurred while saving your progress note."
					return

				@setState {success: true}
				# TODO success animation
				#setTimeout (=> nwWin.close true), 3000
				nwWin.close true

module.exports = {load}
