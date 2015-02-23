load = (win) ->
	React = win.React
	R = React.DOM
	{FaIcon, showWhen} = require('./utils').load(win)

	ProgNoteDetailView = React.createFactory React.createClass
		render: ->
			R.div({className: 'progNoteDetailView'},
				switch @props.itemType
					when null
						R.div({className: 'noSelection'},
							"Select an entry on the left to see more information about it here."
						)
					when 'basicSection'
						R.div({className: 'basicSection'},
							@props.item.get('name')
						)
					else
						throw new Error "unknown item type: #{JSON.stringify @props.itemType}"
			)

	return ProgNoteDetailView

module.exports = {load}
