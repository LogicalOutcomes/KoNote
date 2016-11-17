# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

Imm = require 'immutable'
_ = require 'underscore'

Term = require './term'


load = (win) ->
	$ = win.jQuery
	React = win.React
	R = React.DOM

	ProgEventWidget = require('./progEventWidget').load(win)
	MetricWidget = require('./metricWidget').load(win)
	RevisionHistory = require('./revisionHistory').load(win)
	ColorKeyBubble = require('./colorKeyBubble').load(win)

	{FaIcon, renderLineBreaks, showWhen, formatTimestamp} = require('./utils').load(win)


	ProgNoteDetailView = React.createFactory React.createClass
		displayName: 'ProgNoteDetailView'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: -> {
			descriptionIsVisible: true
			historyCount: 10
		}

		componentWillReceiveProps: (nextProps) ->
			# update was triggered by clicking a target
			if @props.item?
				if @props.item.get('targetId') isnt nextProps.item.get('targetId')
					# Reset history count and scroll
					@_resetHistoryCount()
					if @refs.history? then @refs.history.resetScroll()

		_addHistoryCount: (count) ->
			historyCount = @state.historyCount + count
			@setState {historyCount}

		_resetHistoryCount: ->
			@setState {historyCount: 10}

		render: ->
			{item, progNoteHistories, programsById, metricsById, progEvents, eventTypes} = @props

			unless item
				return R.div({className: 'progNoteDetailView'},
					if progNoteHistories.size > 0
						R.div({className: 'noSelection'},
							"Select an entry on the left to see more information about it here."
						)
				)

			switch item.get('type')
				when 'progNote'
					# First figure out which progNote history to diff through
					progNoteHistory = progNoteHistories.find (progNoteHistory) ->
						progNoteHistory.last().get('id') is item.get('progNoteId')

					return R.div({className: 'progNoteDetailView'},
						RevisionHistory({
							revisions: progNoteHistory.reverse()
							type: 'progNote'
							disableSnapshot: true
							metricsById
							programsById
							dataModelName: Term 'progress note'
							terms: {
								metric: Term 'metric'
								metrics: Term 'metric'
							}
						})
					)

				when 'basicUnit'
					unitId = item.get('unitId')
					itemName = item.get('unitName')

					entries = progNoteHistories.flatMap (progNoteHistory) ->
						initialAuthor = progNoteHistory.first().get('author')
						createdTimestamp = progNoteHistory.first().get('timestamp')
						progNote = progNoteHistory.last()

						switch progNote.get('type')
							when 'basic'
								return Imm.List()
							when 'full'
								return progNote.get('units')
								.filter (unit) => # find relevant units
									return unit.get('id') is unitId
								.map (unit) => # turn them into entries
									matchingProgEvents = progEvents.filter (progEvent) =>
										return progEvent.get('relatedProgNoteId') is progNote.get('id')

									authorProgram = programsById.get progNote.get('authorProgramId')

									return Imm.fromJS {
										status: progNote.get('status')
										progNoteId: progNote.get('id')
										author: initialAuthor
										timestamp: createdTimestamp
										authorProgram
										backdate: progNote.get('backdate')
										notes: unit.get('notes')
										progEvents: matchingProgEvents
									}
							else
								throw new Error "unknown prognote type: #{progNote.get('type')}"

				when 'planSectionTarget'
					unitId = item.get('unitId')
					sectionId = item.get('sectionId')
					targetId = item.get('targetId')
					itemName = item.get('targetName')
					itemDescription = item.get('targetDescription')

					entries = progNoteHistories.flatMap (progNoteHistory) =>
						initialAuthor = progNoteHistory.first().get('author')
						createdTimestamp = progNoteHistory.first().get('timestamp')
						progNote = progNoteHistory.last()

						switch progNote.get('type')
							when 'basic'
								return Imm.List()
							when 'full'
								return progNote.get('units')
								.filter (unit) => # find relevant units
									return unit.get('id') is unitId
								.flatMap (unit) => # turn them into entries
									return unit.get('sections').flatMap (section) =>
										return section.get('targets')
										.filter (target) => # find relevant targets
											return target.get('id') is targetId
										.map (target) =>
											progNoteId = progNote.get('id')
											matchingProgEvents = progEvents.filter (progEvent) ->
												progEvent.get('relatedProgNoteId') is progNoteId

											# Metric entry must have a value to display
											metrics = target.get('metrics').filter (metric) -> metric.get('value')

											authorProgram = programsById.get progNote.get('authorProgramId')

											return Imm.fromJS {
												progNoteId
												status: progNote.get('status')
												targetId: target.get('id')
												author: initialAuthor
												authorProgram
												timestamp: createdTimestamp
												backdate: progNote.get('backdate')
												notes: target.get('notes')
												progEvents: matchingProgEvents
												metrics
											}
							else
								throw new Error "unknown prognote type: #{progNote.get('type')}"

				when 'quickNote'
					itemName = Term 'Quick Notes'

					# Extract all quickNote entries
					entries = progNoteHistories
					.filter (progNoteHistory) -> progNoteHistory.last().get('type') is 'basic'
					.map (progNoteHistory) =>
						initialAuthor = progNoteHistory.first().get('author')
						createdTimestamp = progNoteHistory.first().get('timestamp')
						progNote = progNoteHistory.last()

						progNoteId = progNote.get('id')
						# TODO: progEvents = @props.progEvents.filter (progEvent) =>
						# 	return progEvent.get('relatedProgNoteId') is progNoteId

						authorProgram = programsById.get progNote.get('authorProgramId')

						return Imm.fromJS {
							progNoteId
							status: progNote.get('status')
							author: initialAuthor
							authorProgram
							timestamp: createdTimestamp
							backdate: progNote.get('backdate')
							notes: progNote.get('notes')
						}

				else
					throw new Error "unknown item type: #{JSON.stringify item?.get('type')}"

			# Filter out blank & cancelled notes, and sort by date/backdate
			entries = entries
			.filter (entry) ->
				entry.get('notes').trim().length > 0 and
				entry.get('status') isnt 'cancelled'
			.sortBy (entry) ->
				entry.get('backdate') or entry.get('timestamp')
			.reverse()
			.slice(0, @state.historyCount)


			return R.div({className: 'progNoteDetailView'},
				R.div({className: 'itemDetails'},
					R.div({
						className: 'itemName'
						onClick: => @setState {descriptionIsVisible: not @state.descriptionIsVisible}
					},
						R.h3({}, itemName)
						(if itemDescription?
							R.div({className: 'toggleDescriptionButton'},
								if @state.descriptionIsVisible then "Hide" else "View"
								" description"
							)
						)
					)
					(if itemDescription? and @state.descriptionIsVisible
						R.div({className: 'itemDescription'},
							renderLineBreaks itemDescription
						)
					)
				)
				History({
					ref: 'history'
					entries
					eventTypes
					historyCount: @state.historyCount
					addHistoryCount: @_addHistoryCount
					resetHistoryCount: @_resetHistoryCount
				})
			)


	History = React.createFactory React.createClass
		displayName: 'History'
		mixins: [React.addons.PureRenderMixin]

		componentDidMount: ->
			historyPane = $('.history')
			historyPane.on 'scroll', _.throttle((=>
				if historyPane.scrollTop() + (historyPane.innerHeight() *2) >= historyPane[0].scrollHeight
					@props.addHistoryCount(10)
				return
			), 150)

		resetScroll: ->
			historyPane = $('.history')
			historyPane.scrollTop(0)

		render: ->
			{entries, eventTypes} = @props

			R.div({className: 'history'},
				(entries.map (entry) =>
					entryId = entry.get('progNoteId')
					timestamp = entry.get('backdate') or entry.get('timestamp')
					authorProgram = entry.get('authorProgram') or Imm.Map()

					return R.div({
						key: entryId
						className: 'entry'
					},
						R.div({className: 'header'},
							R.div({className: 'timestamp'},
								formatTimestamp(timestamp)
								ColorKeyBubble({
									colorKeyHex: authorProgram.get('colorKeyHex')
									popover: {
										title: authorProgram.get('name')
										content: authorProgram.get('description')
										placement: 'top'
									}
								})
							)
							R.div({className: 'author'},
								FaIcon('user')
								entry.get('author')
							)
						)
						R.div({className: 'notes'},
							if entry.get('notes').includes "***"
								R.span({className: 'starred'},
									renderLineBreaks entry.get('notes').replace(/\*\*\*/g, '')
								)
							else
								renderLineBreaks entry.get('notes')
						)

						if entry.get('metrics')
							R.div({className: 'metrics'},
								entry.get('metrics').map (metric) =>
									MetricWidget({
										isEditable: false
										key: metric.get('id')
										name: metric.get('name')
										definition: metric.get('definition')
										value: metric.get('value')
									})
							)

						if entry.get('progEvents')
							R.div({className: 'progEvents'},
								entry.get('progEvents').map (progEvent) =>
									ProgEventWidget({
										key: progEvent.get('id')
										format: 'small'
										progEvent
										eventTypes
									})
							)
					)
				).toJS()...
			)

	return ProgNoteDetailView

module.exports = {load}
