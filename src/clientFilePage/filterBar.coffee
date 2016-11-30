# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

_ = require 'underscore'
Imm = require 'immutable'

Term = require '../term'


load = (win) ->
	React = win.React
	{PropTypes} = React
	R = React.DOM

	ColorKeyBubble = require('../colorKeyBubble').load(win)
	{FaIcon, showWhen} = require('../utils').load(win)

	dataTypeOptions = Imm.fromJS [
		{name: 'Progress Notes'}
		{name: 'Targets'}
		{name: 'Events'}
	]


	FilterBar = React.createFactory React.createClass
		displayName: 'FilterBar'

		propTypes: {
			programsById: PropTypes.instanceOf Imm.List()
		}

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
					FilterDropdownMenu({
						title: 'Data'
						dataOptions: dataTypeOptions
					})
					FilterDropdownMenu({
						title: Term 'Programs'
						dataOptions: @props.programsById
					})
					R.div({
						className: 'closeButton'
						onClick: @props.onClose
					},
						FaIcon('times-circle')
					)
				)
			)

	FilterDropdownMenu = ({title, dataOptions, onSelect, selectedValue}) ->
		R.div({className: 'filterDropdownMenu'},
			R.ul({className: 'filterOptions'},
				(if selectedValue
					R.li({}, "All #{title}")
				)
				(dataOptions.toSeq().map (option) ->
					R.li({},
						(if option.has 'colorKeyHex'
							ColorKeyBubble({
								colorKeyHex: option.get('colorKeyHex')
							})
						)
						option.get('name')
					)
				)
			)
			R.div({},
				"All #{title}"
				' '
				FaIcon('caret-down')
			)
		)


	return FilterBar

module.exports = {load}