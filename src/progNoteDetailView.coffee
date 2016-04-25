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
	{FaIcon, renderLineBreaks, showWhen} = require('./utils').load(win)

	ProgNoteDetailView = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		render: ->
			unless @props.item
				return R.div({className: 'progNoteDetailView'},
					if @props.progNoteHistories.size > 0
						R.div({className: 'noSelection'},
							"Select an entry on the left to see more information about it here."
						)
				)

			switch @props.item.get('type')
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

									return Imm.fromJS {
										status: progNote.get('status')
										progNoteId: progNote.get('id')
										author: initialAuthor
										timestamp: createdTimestamp
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
											progEvents = @props.progEvents.filter (progEvent) =>
												return progEvent.get('relatedProgNoteId') is progNoteId

											return Imm.fromJS {
												progNoteId
												status: progNote.get('status')
												targetId: target.get('id')
												author: initialAuthor
												timestamp: createdTimestamp
												backdate: progNote.get('backdate')
												notes: target.get('notes')
												progEvents
												metrics: target.get('metrics')
											}
							else
								throw new Error "unknown prognote type: #{progNote.get('type')}"

				when 'quickNote'
					itemName = Term 'Quick Notes'					

					# Extract all quickNote entries
					entries = @props.progNoteHistories
					.filter (progNoteHistory) -> progNoteHistory.last().get('type') is 'basic'
					.map (progNoteHistory) ->
						initialAuthor = progNoteHistory.first().get('author')
						createdTimestamp = progNoteHistory.first().get('timestamp')
						progNote = progNoteHistory.last()

						progNoteId = progNote.get('id')
						# TODO: progEvents = @props.progEvents.filter (progEvent) =>
						# 	return progEvent.get('relatedProgNoteId') is progNoteId

						return Imm.fromJS {
							progNoteId
							status: progNote.get('status')							
							author: initialAuthor
							timestamp: createdTimestamp
							backdate: progNote.get('backdate')
							notes: progNote.get('notes')
							# TODO: progEvents
						}
						return progNote
						.set('author', initialAuthor)
						.set('timestamp', createdTimestamp)
					
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
				R.div({className: 'itemName'},
					itemName
				)
				R.div({className: 'history'},
					(entries.map (entry) =>
						entryId = entry.get('progNoteId')

						isHighlighted = null
						isHovered = null

						# Figure out highlighting from progNotesTab click/hover data
						isHighlighted = (entryId is @props.highlightedProgNoteId) and not @props.highlightedQuickNoteId?

						if @props.highlightedQuickNoteId?
							isHovered = entry.get('progNoteId') is @props.highlightedQuickNoteId
						else if @props.highlightedTargetId?
							isHovered = (entry.get('targetId') is @props.highlightedTargetId) and isHighlighted

						R.div({
							key: entryId
							className: [
								'entry'
								'highlighted' if isHighlighted
								'isHovered' if isHovered
							].join ' '
						},
							R.div({className: 'header'},
								R.div({className: 'timestamp'},
									if entry.get('backdate') != ''
										Moment(entry.get('backdate'), Persist.TimestampFormat)
										.format('MMMM D, YYYY [at] HH:mm') + ' (late entry)'
									else
										Moment(entry.get('timestamp'), Persist.TimestampFormat)
										.format('MMMM D, YYYY [at] HH:mm')
								)
								R.div({className: 'author'},
									FaIcon('user')
									entry.get('author')
								)
							)
							R.div({className: 'notes'},
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
