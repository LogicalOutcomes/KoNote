# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

_ = require 'underscore'


load = (win) ->
	React = win.React
	R = React.DOM

	{FaIcon} = require('../utils').load(win)


	FilterBar = React.createFactory React.createClass
		displayName: 'FilterBar'

		getInitialState: -> {
			searchText: '' # Stays internal for perf reasons
		}

		componentWillMount: ->
			# Sparingly update the parent progNotesTab UI
			@_updateSearchQuery = _.debounce(@_updateSearchQuery, 350)

		componentDidMount: ->
			@_focusInput()

		_focusInput: ->
			@refs.searchText.focus()

		_updateSearchText: (event) ->
			searchText = event.target.value

			@_updateSearchQuery(searchText)
			@setState {searchText}

		_updateSearchQuery: (searchText) ->
			@props.updateSearchQuery searchText

		render: ->
			R.div({
				className: 'filterBar'
				onClick: @_focusInput
			},
				R.input({
					ref: 'searchText'
					className: 'form-control'
					value: @state.searchText
					onChange: @_updateSearchText
					placeholder: "Search by keywords . . ."
				})
				R.div({
					className: 'closeButton'
					onClick: @props.onClose
				},
					FaIcon('times-circle')
				)
			)

	return FilterBar

module.exports = {load}