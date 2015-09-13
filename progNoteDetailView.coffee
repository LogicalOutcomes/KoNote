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
					if @props.progNotes.size > 0
						R.div({className: 'noSelection'},
							"Select an entry on the left to see more information about it here."
						)
				)

			switch @props.item.get('type')
				when 'basicSection'
					sectionId = @props.item.get('sectionId')
					itemName = @props.item.get('sectionName')
					entries = @props.progNotes.flatMap (progNote) =>
						switch progNote.get('type')
							when 'basic'
								return Imm.List()
							when 'full'
								return progNote.get('sections')
								.filter (section) => # find relevant sections
									return section.get('id') is sectionId
								.map (section) => # turn them into entries
									progEvents = @props.progEvents.filter (progEvent) =>
										return progEvent.get('relatedProgNoteId') is progNote.get('id')

									return Imm.fromJS {
										progNoteId: progNote.get('id')
										author: progNote.get('author')
										timestamp: progNote.get('timestamp')
										notes: section.get('notes')
										progEvents
									}
							else
								throw new Error "unknown prognote type: #{progNote.get('type')}"
				when 'planSectionTarget'
					sectionId = @props.item.get('sectionId')
					targetId = @props.item.get('targetId')
					itemName = @props.item.get('targetName')
					entries = @props.progNotes.flatMap (progNote) =>
						switch progNote.get('type')
							when 'basic'
								return Imm.List()
							when 'full'
								return progNote.get('sections')
								.filter (section) => # find relevant sections
									return section.get('id') is sectionId
								.flatMap (section) => # turn them into entries
									return section.get('targets')
									.filter (target) => # find relevant targets
										return target.get('id') is targetId
									.map (target) =>
										progEvents = @props.progEvents.filter (progEvent) =>
											return progEvent.get('relatedProgNoteId') is progNote.get('id')

										return Imm.fromJS {
											progNoteId: progNote.get('id')
											author: progNote.get('author')
											timestamp: progNote.get('timestamp')
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
				return entry.get('notes').trim() isnt ''
			.sortBy (entry) -> # sort by reverse chronological order
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
										title: progEvent.get('title')
										description: progEvent.get('description')
										start: progEvent.get('startTimestamp')
										end: progEvent.get('endTimestamp')
									})
							)
						)
					).toJS()...
				)
			)

	return ProgNoteDetailView

module.exports = {load}
