# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

_ = require 'underscore'


load = (win) ->
	React = win.React
	R = React.DOM


	FilterBar = React.createFactory React.createClass
		displayName: 'FilterBar'

		getInitialState: -> {
			searchText: '' # Stays internal for perf reasons
		}

		componentWillMount: ->
			# Sparingly update the parent progNotesTab UI
			@_updateSearchQuery = _.debounce(@_updateSearchQuery, 350)

		_updateSearchText: (event) ->
			searchText = event.target.value

			@_updateSearchQuery(searchText)
			@setState {searchText}

		_updateSearchQuery: (searchText) ->
			@props.updateSearchQuery searchText

		render: ->
			R.div({className: 'filterBar'},
				R.input({
					className: 'form-control'
					value: @state.searchText
					onChange: @_updateSearchText
					placeholder: "Search by keywords . . ."
				})
			)

	return FilterBar

module.exports = {load}