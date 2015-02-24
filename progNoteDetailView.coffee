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
							# TODO use real data
							R.div({className: 'sectionName'},
								"Section Name Goes Here"
							)
							R.div({className: 'history'},
								R.div({className: 'revision'},
									# TODO author!!
									R.div({className: 'timestamp'},
										"February 18, 2015 at 3:02pm"
									)
									R.div({className: 'notes'},
										"""
											Notes about what happened that day would go here.
											This makes it easy to see how things changed
											over time, or just to see what happened yesterday.
										"""
									)
								)
								R.div({className: 'revision'},
									R.div({className: 'timestamp'},
										"February 17, 2015 at 3:07pm"
									)
									R.div({className: 'notes'},
										"""
											Another days worth of notes about what
											happened would go here.  These notes
											can be as long or short as you like.
										"""
									)
								)
								R.div({className: 'revision'},
									R.div({className: 'timestamp'},
										"February 16, 2015 at 2:31pm"
									)
									R.div({className: 'notes'},
										"""
											More notes about what happened that day would go here.
											This makes it easy to see how things changed
											over time, or just to see what happened yesterday.
										"""
									)
								)
							)
						)
					else
						throw new Error "unknown item type: #{JSON.stringify @props.itemType}"
			)

	return ProgNoteDetailView

module.exports = {load}
