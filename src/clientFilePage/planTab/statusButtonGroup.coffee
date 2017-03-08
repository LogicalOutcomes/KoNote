# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Presentational component for plan section or target status buttons

Term = require '../../term'


load = (win) ->
	React = win.React
	R = React.DOM

	WithTooltip = require('../../withTooltip').load(win)
	OpenDialogLink = require('../../openDialogLink').load(win)

	{FaIcon} = require('../../utils').load(win)


	StatusButtonGroup = ({planElementType, data, parentData, isExisting, status, onRemove, dialog, isDisabled}) ->
		isDefaultStatus = status is 'default'

		R.div({className: 'statusButtonGroup'},
			# Will show remove (x) button for an empty section, rare case
			if not isExisting and onRemove?
				R.div({
					className: "statusButton #{className}"
					onClick: onRemove
				},
					FaIcon(icon)
				)

			else

				if status is 'default'
					[
						{
							className: 'deactivate'
							tooltip: 'Deactivate'
							icon: 'times'
							dialog
							title: "Deactivate #{planElementType}"
							message: """
								This will remove the #{planElementType.toLowerCase()} from the #{Term 'client'}
								#{Term 'plan'}, and future #{Term 'progress notes'}.
								It may be re-activated again later.
							"""
							reasonLabel: "Reason for deactivation:"
							newStatus: 'deactivated'
							data, parentData
							isDisabled
						}
						{
							className: 'complete'
							tooltip: 'Complete'
							icon: 'check'
							dialog
							title: "Mark #{planElementType} as Completed"
							message: """
								This will mark the #{planElementType.toLowerCase()} as 'completed'. This often
								means that the desired outcome has been reached.
							"""
							reasonLabel: "Reason for completed:"
							newStatus: 'completed'
							data, parentData
							isDisabled
						}
					].map (b) -> StatusButton(Object.assign {}, b, {key: b.className})

				else
					StatusButton({
						className: 'reactivate'
						tooltip: "Re-activate #{planElementType}"
						icon: 'sign-in'
						dialog
						title: "Reactivate #{planElementType}"
						message: """
							This will reactivate the #{planElementType.toLowerCase()} so it appears in the #{Term 'client'}
							#{Term 'plan'}, and future #{Term 'progress notes'}.
						"""
						newStatus: 'default'
						reasonLabel: "Reason for reactivation"
						data, parentData
						isDisabled
					})

		)

	StatusButton = ({className, tooltip, icon, onClick, dialog, title, message, newStatus, data, parentData, reasonLabel, isDisabled}) ->
		WithTooltip({
			title: tooltip unless isDisabled
			placement: 'top'
			container: 'body'
		},
			OpenDialogLink({
				className: "statusButton #{className}"
				dialog
				newStatus
				data, parentData
				title
				message
				reasonLabel
				disabled: isDisabled
			},
				FaIcon(icon)
			)
		)


	return StatusButtonGroup


module.exports = {load}