Imm = require 'immutable'
Moment = require 'moment'

Config = require '../config'
Persist = require '../persist'

load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM
	ExpandingTextArea = require('../expandingTextArea').load(win)
	MetricWidget = require('../metricWidget').load(win)
	{FaIcon, openWindow, renderLineBreaks, showWhen} = require('../utils').load(win)

	ProgNotesView = React.createFactory React.createClass
		componentDidMount: ->
			quickNoteToggle = $(@refs.quickNoteToggle.getDOMNode())
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
				R.div({className: 'toolbar'},
					R.button({
						className: 'newProgNote btn btn-primary'
						onClick: @_openNewProgNote
					},
						FaIcon 'file'
						"New progress note"
					)
					R.button({
						className: 'addQuickNote btn btn-default'
						ref: 'quickNoteToggle'
						onClick: @_toggleQuickNotePopover
					},
						FaIcon 'plus'
						"Add quick note"
					)
				)
				R.div({className: 'progNotes'},
					(@props.progressNotes.reverse().map (progNote) =>
						switch progNote.get('type')
							when 'basic'
								R.div({className: 'basic progNote', key: progNote.get('id')},
									R.div({className: 'header'},
										R.div({className: 'timestamp'},
											Moment(progNote.get('timestamp'))
											.format 'MMMM D, YYYY [at] HH:mm'
										)
										R.div({className: 'author'},
											' by '
											progNote.get('author')
										)
									)
									R.div({className: 'notes'},
										renderLineBreaks progNote.get('notes')
									)
								)
							when 'full'
								R.div({className: 'full progNote', key: progNote.get('id')},
									R.div({className: 'header'},
										R.div({className: 'timestamp'},
											Moment(progNote.get('timestamp'))
											.format 'MMMM D, YYYY [at] HH:mm'
										)
										R.div({className: 'author'},
											' by '
											progNote.get('author')
										)
									)
									R.div({className: 'sections'},
										(progNote.get('sections').map (section) =>
											switch section.get('type')
												when 'basic'
													R.div({className: 'basic section', key: section.get('id')},
														R.h1({className: 'name'}, section.get('name'))
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
															"This section is empty because the client has no plan targets."
														)
														R.div({className: 'targets'},
															(section.get('targets').map (target) =>
																R.div({className: 'target', key: target.get('id')},
																	R.h2({className: 'name'},
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
									)
								)
							else
								throw new Error "unknown prognote type: #{progNote.get('type')}"
					).toJS()...
				)
			)
		_openNewProgNote: ->
			openWindow {page: 'newProgNote', clientId: @props.clientId}
		_toggleQuickNotePopover: ->
			quickNoteToggle = $(@refs.quickNoteToggle.getDOMNode())

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

					@_createQuickNote popover.find('textarea').val()
				popover.find('.cancel.btn').on 'click', (event) =>
					event.preventDefault()

					@_toggleQuickNotePopover()
				popover.find('textarea').focus()
		_createQuickNote: (notes) ->
			note = Imm.fromJS {
				type: 'basic'
				clientId: @props.clientId
				author: 'xxx'
				notes
			}

			@props.registerTask 'quickNote-save'
			Persist.ProgNote.create note, (err) =>
				if err
					console.error err.stack
					Bootbox.alert "An error occurred while saving your quick note."
					return

				@_toggleQuickNotePopover()
				@props.unregisterTask 'quickNote-save'

	return {ProgNotesView}

module.exports = {load}
