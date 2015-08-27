# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

Imm = require 'immutable'
Moment = require 'moment'

Config = require '../config'
Term = require '../term'
Persist = require '../persist'

load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM
	CrashHandler = require('../crashHandler').load(win)
	ExpandingTextArea = require('../expandingTextArea').load(win)
	MetricWidget = require('../metricWidget').load(win)
	ProgNoteDetailView = require('../progNoteDetailView').load(win)
	PrintButton = require('../printButton').load(win)
	{FaIcon, openWindow, renderLineBreaks, showWhen} = require('../utils').load(win)

	ProgNotesView = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				selectedItem: null
			}

		componentDidMount: ->
			quickNoteToggle = $('.addQuickNote')
			quickNoteToggle.data 'isVisible', false
			quickNoteToggle.popover {
				placement: 'bottom'
				html: true
				trigger: 'manual'
				content: '''
					<textarea class="form-control"></textarea>
					<div class="buttonBar">
						<button class="cancel btn btn-default"><i class="fa fa-trash"></i> Discard</button>
						<button class="save btn btn-primary"><i class="fa fa-check"></i> Save</button>
					</div>
				'''
			}

		render: ->
			return R.div({className: "view progNotesView #{showWhen @props.isVisible}"},
				R.div({className: "toolbar #{showWhen @props.progNotes.size > 0}"},
					R.button({
						className: 'newProgNote btn btn-primary'
						onClick: @_openNewProgNote
						disabled: @props.isReadOnly
					},
						FaIcon 'file'
						"New #{Term 'progress note'}"
					)
					R.button({
						className: "addQuickNote btn btn-default #{showWhen @props.progNotes.size > 0}"						
						onClick: @_toggleQuickNotePopover
						disabled: @props.isReadOnly
					},
						FaIcon 'plus'
						"Add #{Term 'quick note'}"
					)
				)
				R.div({className: 'panes'},
					R.div({className: 'progNotes'},
						R.div({
							className: "empty #{showWhen @props.progNotes.size is 0}"},
							R.div({className: 'message'},
								"This #{Term 'client'} does not currently have any #{Term 'progress notes'}."
							)
							R.button({
								className: 'newProgNote btn btn-primary btn-lg'
								onClick: @_openNewProgNote
								disabled: @props.isReadOnly
							},
								FaIcon 'file'
								"New #{Term 'progress note'}"
							)
							R.button({
								className: "addQuickNote btn btn-default btn-lg #{showWhen @props.progNotes.size is 0}"								
								onClick: @_toggleQuickNotePopover
								disabled: @props.isReadOnly
							},
								FaIcon 'plus'
								"Add #{Term 'quick note'}"
							)
						)
						(@props.progNotes.reverse().map (progNote) =>
							# Filter out only events for this progNote
							progEvents = @props.progEvents.filter (progEvent) =>
								return progEvent.get('relatedProgNoteId') is progNote.get('id')

							switch progNote.get('type')
								when 'basic'
									BasicProgNoteView({
										progNote
										clientFile: @props.clientFile
										key: progNote.get('id')
									})
								when 'full'
									FullProgNoteView({
										progNote
										progEvents
										clientFile: @props.clientFile
										key: progNote.get('id')
										setSelectedItem: @_setSelectedItem
									})
								else
									throw new Error "unknown prognote type: #{progNote.get('type')}"
						).toJS()...
					)
					ProgNoteDetailView({
						item: @state.selectedItem
						progNotes: @props.progNotes
						progEvents: @props.progEvents
					})
				)
			)
		_openNewProgNote: ->
			openWindow {page: 'newProgNote', clientFileId: @props.clientFileId}
		_toggleQuickNotePopover: ->			
			quickNoteToggle = $('.addQuickNote:not(.hide)')

			if quickNoteToggle.data('isVisible')
				quickNoteToggle.popover('hide')
				quickNoteToggle.data('isVisible', false)
			else
				global.document = win.document
				quickNoteToggle.popover('show')
				quickNoteToggle.data('isVisible', true)

				popover = quickNoteToggle.siblings('.popover')
				popover.find('.save.btn').on 'click', (event) =>
					event.preventDefault()

					@props.createQuickNote popover.find('textarea').val(), (err) =>
						if err
							if err instanceof Persist.IOError
								Bootbox.alert """
									An error occurred.  Please check your network connection and try again.
								"""
								return

							CrashHandler.handle err
							return

						quickNoteToggle.popover('hide')
						quickNoteToggle.data('isVisible', false)

				popover.find('.cancel.btn').on 'click', (event) =>
					event.preventDefault()
					quickNoteToggle.popover('hide')
					quickNoteToggle.data('isVisible', false)

				popover.find('textarea').focus()

		_setSelectedItem: (selectedItem) ->
			@setState {selectedItem}

	# These are called 'quick notes' in the UI
	BasicProgNoteView = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		render: ->
			R.div({className: 'basic progNote'},
				R.div({className: 'header'},
					R.div({className: 'timestamp'},
						Moment(@props.progNote.get('timestamp'), Persist.TimestampFormat)
						.format 'MMMM D, YYYY [at] HH:mm'
					)
					R.div({className: 'author'},
						' by '
						@props.progNote.get('author')
					)					
				)
				R.div({className: 'notes'},
					PrintButton({
						dataSet: [
							{
								format: 'progNote'
								data: @props.progNote
								clientFile: @props.clientFile
							}
						]
						isVisible: true
					})
					renderLineBreaks @props.progNote.get('notes')
				)
			)

	FullProgNoteView = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		render: ->
			R.div({className: 'full progNote'},
				R.div({className: 'header'},
					R.div({className: 'timestamp'},
						Moment(@props.progNote.get('timestamp'), Persist.TimestampFormat)
						.format 'MMMM D, YYYY [at] HH:mm'
					)
					R.div({className: 'author'},
						' by '
						@props.progNote.get('author')
					)
				)
				R.div({className: 'sections'},
					PrintButton({
						dataSet: [
							{
								format: 'progNote'
								data: @props.progNote
								clientFile: @props.clientFile
							}
						]
						isVisible: true
					})
					(@props.progNote.get('sections').map (section) =>
						switch section.get('type')
							when 'basic'
								R.div({className: 'basic section', key: section.get('id')},
									R.h1({
										className: 'name'
										onClick: @_selectBasicSection.bind null, section
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
											R.div({className: 'target', key: target.get('id')},
												R.h2({
													className: 'name'
													onClick: @_selectPlanSectionTarget.bind(
														null, section, target
													)
												},
													target.get('name')
												)
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
					R.div({className: 'events'}
						(@props.progEvents.map (progEvent) =>
							R.div({}, "Prog Event: #{progEvent.get('title')}")
						).toJS()...
					)
				)
			)
		_selectBasicSection: (section) ->
			@props.setSelectedItem Imm.fromJS {
				type: 'basicSection'
				sectionId: section.get('id')
				sectionName: section.get('name')
			}
		_selectPlanSectionTarget: (section, target) ->
			@props.setSelectedItem Imm.fromJS {
				type: 'planSectionTarget'
				sectionId: section.get('id')
				targetId: target.get('id')
				targetName: target.get('name')
			}

	return {ProgNotesView}

module.exports = {load}
