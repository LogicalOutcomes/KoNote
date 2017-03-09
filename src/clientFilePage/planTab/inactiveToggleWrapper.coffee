# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Wrapper component for a list of inactive (completed/deactivated) sections or targets

Term = require '../../term'


load = (win) ->
	React = win.React
	R = React.DOM

	{FaIcon} = require('../../utils').load(win)


	InactiveToggleWrapper = ({dataType, status, size, isExpanded, onToggle, children}) ->
		iconName = (if isExpanded then 'minus' else 'plus') + '-square-o'

		return R.div({
			id: "sections-#{status}"
			className: [
				"inactiveToggleWrapper status-#{status}"
				'isExpanded' if isExpanded
			].join ' '
		},
			R.div({
				className: 'toggleHeader'
				onClick: onToggle
			},
				# Rotates 90'CW when expanded
				FaIcon(iconName, {className: 'toggleIcon'})

				R.strong({}, size)
				" #{capitalize(status)} "

				# Singular or plural
				capitalize Term (
					if size > 1 then "#{dataType}s" else dataType
				)
			)

			# Can't do with CSS, expandingTextArea needs to know its height on render
			(if isExpanded
				R.div({className: "inactiveDataList"},
					children
				)
			)
		)


	capitalize = (word) -> word.charAt(0).toUpperCase() + word.slice(1)


	return InactiveToggleWrapper

module.exports = {load}