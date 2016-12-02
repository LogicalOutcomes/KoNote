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
		{name: 'Progress Notes', id: 'progNotes'}
		{name: 'Targets', id: 'targets'}
		{name: 'Events', id: 'event'}
	]


	FilterBar = React.createFactory React.createClass
		displayName: 'FilterBar'

		propTypes: {
			onUpdateSearchQuery: PropTypes.func
			programIdFilter: PropTypes.string
			dataTypeFilter: PropTypes.oneOf ['progNotes', 'targets', 'events']
			programsById: PropTypes.instanceOf Imm.List()

			onClose: PropTypes.func
			onUpdateSearchQuery: PropTypes.func
			onSelectProgramId: PropTypes.func
			onSelectDataType: PropTypes.func
		}

		getInitialState: -> {
			searchText: '' # Stays internal for perf reasons
		}

		componentWillMount: ->
			# Sparingly update the parent progNotesTab UI
			@_updateSearchQuery = _.debounce(@props.onUpdateSearchQuery, 350)

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
						onSelect: @props.onSelectDataType
					})
					FilterDropdownMenu({
						title: Term 'Programs'
						dataOptions: @props.programsById
						onSelect: @props.onSelectProgramId
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
					R.li({
						onClick: onSelect.bind null, null
					},
						"All #{title}"
					)
				)
				(dataOptions.toSeq().map (option) ->
					R.li({
						onClick: onSelect.bind null, option.get('id')
					},
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