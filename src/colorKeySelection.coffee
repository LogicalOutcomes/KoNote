# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Wrapper component for ColorKeyBubble to toggle selection, and detect duplicate selection

Imm = require 'immutable'


load = (win) ->
	React = win.React
	Bootbox = win.bootbox
	R = React.DOM

	ColorKeyBubble = require('./colorKeyBubble').load(win)


	ColorKeySelection = React.createFactory React.createClass
		displayName: 'ColorKeySelection'
		mixins: [React.addons.PureRenderMixin]

		propTypes: {
			colors: React.PropTypes.instanceOf(Imm.List).isRequired
			data: React.PropTypes.instanceOf(Imm.List).isRequired
			selectedColorKeyHex: React.PropTypes.string
			onSelect: React.PropTypes.func.isRequired
		}

		getDefaultProps: ->
			return {
				colors: Imm.List()
				data: Imm.List()
				selectedColorKeyHex: null
			}

		render: ->
			R.div({className: 'colorKeySelection'},
				(@props.colors.map (colorKeyHex) =>
					isSelected = @props.selectedColorKeyHex is colorKeyHex
					alreadyInUse = @_colorInUse(colorKeyHex)

					icon = if isSelected
						'check'
					else if alreadyInUse
						'ban'
					else
						null

					ColorKeyBubble({
						key: colorKeyHex
						colorKeyHex
						icon
						onClick: @_onClick.bind null, colorKeyHex, isSelected, alreadyInUse
					})
				)
			)

		_colorInUse: (colorKeyHex) ->
			@props.data.find (dataPoint) -> dataPoint.get('colorKeyHex') is colorKeyHex

		_onClick: (colorKeyHex, isSelected, alreadyInUse) ->
			# Toggle behaviour
			if isSelected then colorKeyHex = null

			if alreadyInUse
				Bootbox.confirm {
					title: "Colour key already assigned"
					message: "
						This colour key has already been assigned to \"#{alreadyInUse.get('name')}\".
						Are you sure you still want to use this colour?
					"
					callback: (ok) =>
						if ok then @props.onSelect(colorKeyHex)
				}
				return

			@props.onSelect(colorKeyHex)


	return ColorKeySelection

module.exports = {load}
