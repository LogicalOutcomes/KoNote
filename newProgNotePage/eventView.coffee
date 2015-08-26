# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Read/Write event information view contained within eventTab

load = (win) ->
	$ = win.jQuery
	React = win.React
	R = React.DOM
	Bootbox = win.bootbox

	Moment = require 'moment'
	_ = require 'underscore'	

	ExpandingTextArea = require('../expandingTextArea').load(win)
	{FaIcon, renderName, showWhen} = require('../utils').load(win)
	{TimestampFormat} = require '../persist/utils'

	EventTabView = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]
		getInitialState: ->
			# Grab data props if exists
			return {
				title: ''
				description: ''
				startTimestamp: ''
				endTimestamp: ''
				hasDateSpan: false
			}

		componentDidUpdate: ->
			# Initialize datepickers, update @state when value changes

			$(@refs.startTimestamp.getDOMNode()).datetimepicker({
				widgetPositioning: {
					horizontal: 'right'
				}
			}).on 'dp.change', (thisInput) =>
				@setState {startTimestamp: thisInput.date.format(TimestampFormat)}

			$(@refs.endTimestamp.getDOMNode()).datetimepicker({
				widgetPositioning: {
					horizontal: 'right'
				}
			}).on 'dp.change', (thisInput) =>
				@setState {endTimestamp: thisInput.date.format(TimestampFormat)}					

		render: ->
			return R.div({
				className: "eventView #{showWhen @props.isBeingEdited or not @props.editMode}"
			},
				R.form({className: showWhen @props.isBeingEdited},
					R.button({
						className: 'btn btn-danger'
						onClick: @_closeForm
					}, FaIcon('times'))
					R.button({
						className: 'btn btn-warning'
						onClick: @_toggleHasDateSpan
					}, 
						if @state.hasDateSpan then "Single Date" else "Date Span"
					)
					R.div({className: 'form-group'},
						R.label({}, "Title")
						R.input({
							value: @state.title
							onChange: @_updateTitle
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "Description")
						ExpandingTextArea({
							value: @state.description
							onChange: @_updateDescription
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "Start Date")
						R.input({
							type: 'text'
							ref: 'startTimestamp'
							className: 'form-control'
						})
					)
					R.div({className: "form-group #{showWhen @state.hasDateSpan}"},
						R.label({}, "End Date")
						R.input({
							className: showWhen @state.hasDateSpan
							type: 'text'
							ref: 'endTimestamp'
							className: "form-control"
						})
					)
					R.button({
						className: 'btn btn-success'
						onClick: @_saveEventData
						disabled: not @state.title or not @state.startTimestamp or (@state.hasDateSpan and not @state.endTimestamp)
					}, 
						"Save"
						FaIcon('check')
					)
				)

				R.div({className: "details #{showWhen not @props.isBeingEdited}"},
					"title: #{@props.data.title}\n"
					"description: #{@props.data.description}\n"
					"startTimestamp: #{@_showTimestamp @props.data.startTimestamp}\n"
					if @props.data.endTimestamp
						"endTimestamp: #{@_showTimestamp @props.data.endTimestamp}\n"
				)				
		)

		_showTimestamp: (timestamp) ->
			moment = Moment(timestamp, TimestampFormat)

			if moment.isValid
				return Moment(moment, TimestampFormat).format('YYYY-MM-DD HH:mm')
			else
				return "Invalid Moment"

		_toggleHasDateSpan: (event) ->
			event.preventDefault()
			@setState {hasDateSpan: not @state.hasDateSpan}

		_updateTitle: (event) ->
			@setState {title: event.target.value}

		_updateDescription: (event) ->
			@setState {description: event.target.value}

		_closeForm: (event) ->
			event.preventDefault()

			if (@state.startDate or @state.endDate or @state.description)
				Bootbox.confirm "Cancel event editing?", (result) =>
					if result
						# Make sure all states are reset, then cancel
						@replaceState @props.data, =>
							@props.cancel @props.atIndex
			else
				@replaceState @props.data, =>
					@props.cancel @props.atIndex

		_compiledFormData: ->
			return {
				title: @state.title
				startTimestamp: @state.startTimestamp
				endTimestamp: if @state.hasDateSpan then @state.endTimestamp else ''
				description: @state.description
			}				

		_saveEventData: (event) ->
			event.preventDefault()

			newData = @_compiledFormData()

			@props.save newData, @props.atIndex

	return EventTabView

module.exports = {load}