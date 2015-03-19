Imm = require 'immutable'
Moment = require 'moment'

Config = require './config'
Persist = require './persist'

load = (win) ->
	React = win.React
	R = React.DOM
	{FaIcon, showWhen} = require('./utils').load(win)

	ProgNoteDetailView = React.createFactory React.createClass
		render: ->
			unless @props.item
				return R.div({className: 'progNoteDetailView'},
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
									return Imm.fromJS {
										progNoteId: progNote.get('id')
										author: progNote.get('author')
										timestamp: progNote.get('timestamp')
										notes: section.get('notes')
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
										return Imm.fromJS {
											progNoteId: progNote.get('id')
											author: progNote.get('author')
											timestamp: progNote.get('timestamp')
											notes: target.get('notes')
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
							# TODO author!!
							R.div({className: 'timestamp'},
								Moment(entry.get('timestamp'))
								.format('MMMM D, YYYY [at] HH:mm')
							)
							R.div({className: 'notes'},
								entry.get('notes')
							)
						)
					).toJS()...
				)
			)

	return ProgNoteDetailView

module.exports = {load}
