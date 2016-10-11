# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

Imm = require 'immutable'
Moment = require 'moment'

Config = require './config'
Term = require './term'
Persist = require './persist'


load = (win) ->
	React = win.React
	R = React.DOM

	ProgEventsWidget = require('./progEventsWidget').load(win)
	MetricWidget = require('./metricWidget').load(win)
	RevisionHistory = require('./revisionHistory').load(win)
	ColorKeyBubble = require('./colorKeyBubble').load(win)

	{FaIcon, renderLineBreaks, showWhen, formatTimestamp} = require('./utils').load(win)


	ProgNoteDetailView = React.createFactory React.createClass
		displayName: 'ProgNoteDetailView'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: -> {
			descriptionIsVisible: true
		}

		render: ->
			unless @props.item
				return R.div({className: 'progNoteDetailView'},
					if @props.progNoteHistories.size > 0
						R.div({className: 'noSelection'},
							"Select an entry on the left to see more information about it here."
						)
				)

			switch @props.item.get('type')
				when 'progNote'
					# First figure out which progNote history to diff through
					progNoteHistory = @props.progNoteHistories.find (progNoteHistory) =>
						progNoteHistory.last().get('id') is @props.item.get('progNoteId')

					return R.div({className: 'progNoteDetailView'},
						RevisionHistory({
							revisions: progNoteHistory.reverse()
							type: 'progNote'
							disableSnapshot: true
							metricsById: @props.metricsById
							programsById: @props.programsById
							dataModelName: Term 'progress note'
							terms: {
								metric: Term 'metric'
								metrics: Term 'metric'
							}
						})
					)

				when 'basicUnit'
					unitId = @props.item.get('unitId')
					itemName = @props.item.get('unitName')

					entries = @props.progNoteHistories.flatMap (progNoteHistory) =>
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
									progEvents = @props.progEvents.filter (progEvent) =>
										return progEvent.get('relatedProgNoteId') is progNote.get('id')

									authorProgram = @props.programsById.get progNote.get('authorProgramId')

									return Imm.fromJS {
										status: progNote.get('status')
										progNoteId: progNote.get('id')
										author: initialAuthor
										timestamp: createdTimestamp
										authorProgram
										backdate: progNote.get('backdate')
										notes: unit.get('notes')
										progEvents
									}
							else
								throw new Error "unknown prognote type: #{progNote.get('type')}"

				when 'planSectionTarget'
					unitId = @props.item.get('unitId')
					sectionId = @props.item.get('sectionId')
					targetId = @props.item.get('targetId')
					itemName = @props.item.get('targetName')
					itemDescription = @props.item.get('targetDescription')

					entries = @props.progNoteHistories.flatMap (progNoteHistory) =>
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
											progEvents = @props.progEvents.filter (progEvent) ->
												progEvent.get('relatedProgNoteId') is progNoteId

											# Metric entry must have a value to display
											metrics = target.get('metrics').filter (metric) -> metric.get('value')

											authorProgram = @props.programsById.get progNote.get('authorProgramId')

											return Imm.fromJS {
												progNoteId
												status: progNote.get('status')
												targetId: target.get('id')
												author: initialAuthor
												authorProgram
												timestamp: createdTimestamp
												backdate: progNote.get('backdate')
												notes: target.get('notes')
												progEvents
												metrics
											}
							else
								throw new Error "unknown prognote type: #{progNote.get('type')}"

				when 'quickNote'
					itemName = Term 'Quick Notes'

					# Extract all quickNote entries
					entries = @props.progNoteHistories
					.filter (progNoteHistory) -> progNoteHistory.last().get('type') is 'basic'
					.map (progNoteHistory) =>
						initialAuthor = progNoteHistory.first().get('author')
						createdTimestamp = progNoteHistory.first().get('timestamp')
						progNote = progNoteHistory.last()

						progNoteId = progNote.get('id')
						# TODO: progEvents = @props.progEvents.filter (progEvent) =>
						# 	return progEvent.get('relatedProgNoteId') is progNoteId

						authorProgram = @props.programsById.get progNote.get('authorProgramId')

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
					throw new Error "unknown item type: #{JSON.stringify @props.item?.get('type')}"

			# Filter out blank & cancelled notes, and sort by date/backdate
			entries = entries
			.filter (entry) ->
				entry.get('notes').trim().length > 0 and
				entry.get('status') isnt 'cancelled'
			.sortBy (entry) ->
				entry.get('backdate') or entry.get('timestamp')
			.reverse()


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
				R.div({className: 'history'},
					(entries.map (entry) =>
						entryId = entry.get('progNoteId')

						isHighlighted = null
						isHovered = null

						# Figure out highlighting from progNotesTab click/hover data
						isHighlighted = (entryId is @props.highlightedProgNoteId) and not @props.highlightedQuickNoteId?

						## TODO: Restore this hover feature
						# if @props.highlightedQuickNoteId?
						# 	isHovered = entry.get('progNoteId') is @props.highlightedQuickNoteId
						# else if @props.highlightedTargetId?
						# 	isHovered = (entry.get('targetId') is @props.highlightedTargetId) and isHighlighted

						timestamp = entry.get('backdate') or entry.get('timestamp')

						authorProgram = entry.get('authorProgram') or Imm.Map()

						return R.div({
							key: entryId
							className: [
								'entry'
								## TODO: Restore this hover feature
								# 'highlighted' if isHighlighted
								# 'isHovered' if isHovered
							].join ' '
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
										ProgEventsWidget({
											format: 'small'
											data: progEvent
											key: progEvent.get('id')
											eventTypes: @props.eventTypes
										})
								)
						)
					).toJS()...
				)
			)

	return ProgNoteDetailView

module.exports = {load}
