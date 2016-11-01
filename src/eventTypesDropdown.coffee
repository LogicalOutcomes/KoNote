# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0


load = (win) ->
	React = win.React
	R = React.DOM

	B = require('./utils/reactBootstrap').load(win, 'DropdownButton', 'MenuItem')
	{FaIcon} = require('./utils').load(win)


	EventTypesDropdown = ({eventTypes, selectedEventType, onSelect}) ->
		title = if selectedEventType? then selectedEventType.get('name') else "None"

		# Discard inactive eventTypes
		eventTypes = eventTypes.filter (eventType) =>
			eventType.get('status') is 'default'


		B.DropdownButton({title},
			(if selectedEventType
				B.MenuItem({
					onClick: onSelect.bind null, ''
				},
					"None "
					FaIcon('ban')
				)
			)

			(if selectedEventType
				B.MenuItem({divider: true})
			)

			(eventTypes.map (eventType) =>
				B.MenuItem({
					key: eventType.get('id')
					onClick: onSelect.bind null, eventType.get('id') # ?
				},
					R.div({
						style:
							borderRight: "5px solid #{eventType.get('colorKeyHex')}"
					},
						eventType.get('name')
					)
				)
			)
		)

	return EventTypesDropdown


module.exports = {load}