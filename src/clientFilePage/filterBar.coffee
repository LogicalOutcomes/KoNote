# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

_ = require 'underscore'


load = (win) ->
	React = win.React
	R = React.DOM

	{FaIcon, showWhen} = require('../utils').load(win)


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

		componentDidUpdate: (oldProps, oldState) ->
			# Focus input when made visible
			if @props.isVisible isnt oldProps.isVisible and @props.isVisible
				@_focusInput()

		_focusInput: ->
			@refs.searchText.focus()

		_updateSearchText: (event) ->
			searchText = event.target.value

			@setState {searchText}
			@_updateSearchQuery(searchText)

		_updateSearchQuery: (searchText) ->
			@props.updateSearchQuery searchText

		render: ->
			R.div({
				className: "filterBar #{showWhen @props.isVisible}"
				onClick: @_focusInput
			},
				R.section({},
					R.input({
						ref: 'searchText'
						className: 'form-control'
						value: @state.searchText
						onChange: @_updateSearchText
						placeholder: "Search by keywords . . ."
					})
				)
				R.section({},
					R.div({}, "Select v")
					R.div({}, "Select v")
					R.div({
						className: 'closeButton'
						onClick: @props.onClose
					},
						FaIcon('times-circle')
					)
				)
			)

	return FilterBar

module.exports = {load}