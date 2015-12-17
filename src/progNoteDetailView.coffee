# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

Imm = require 'immutable'
Moment = require 'moment'

Config = require './config'
Persist = require './persist'

load = (win) ->
	React = win.React
	R = React.DOM
	ProgEventsWidget = require('./progEventsWidget').load(win)
	MetricWidget = require('./metricWidget').load(win)
	{FaIcon, showWhen} = require('./utils').load(win)

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
						createdAt = progNoteHistory.first().get('timestamp')
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
										timestamp: createdAt
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
						createdAt = progNoteHistory.first().get('timestamp')
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
											progEvents = @props.progEvents.filter (progEvent) =>
												return progEvent.get('relatedProgNoteId') is progNote.get('id')

											return Imm.fromJS {
												status: progNote.get('status')
												progNoteId: progNote.get('id')
												author: initialAuthor
												timestamp: progNote.get('timestamp')
												backdate: progNote.get('backdate')
												notes: target.get('notes')
												progEvents
												metrics: target.get('metrics')
											}
							else
								throw new Error "unknown prognote type: #{progNote.get('type')}"
				else
					throw new Error "unknown item type: #{JSON.stringify @props.item?.get('type')}"

			entries = entries
			.filter (entry) -> # remove blank entries
				return entry.get('notes').trim().length > 0
			.filter (entry) -> # remove cancelled entries
				switch entry.get('status')
					when 'default'
						return true
					when 'cancelled'
						return false
					else
						throw new Error "unknown prognote status: #{entry.get('status')}"
			.sortBy (entry) ->
				if entry.get('backdate')
					return entry.get('backdate')
				else
					return entry.get('timestamp')
			.reverse()

			return R.div({className: 'progNoteDetailView'},
				R.div({className: 'itemName'},
					itemName
				)
				R.div({className: 'history'},
					(entries.map (entry) =>
						R.div({className: 'entry'},
							R.div({className: 'header'}								
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
							R.div({className: 'notes'}, entry.get('notes'))
							R.div({className: 'metrics'},
								if entry.get('metrics')
									entry.get('metrics').map (metric) =>
										MetricWidget({
											isEditable: false
											key: metric.get('id')
											name: metric.get('name')
											definition: metric.get('definition')
											value: metric.get('value')
										})
							)
							R.div({className: 'progEvents'},
								entry.get('progEvents').map (progEvent) =>
									ProgEventsWidget({
										format: 'small'
										data: progEvent
										key: progEvent.get('id')
									})
							)
						)
					).toJS()...
				)
			)

	return ProgNoteDetailView

module.exports = {load}
