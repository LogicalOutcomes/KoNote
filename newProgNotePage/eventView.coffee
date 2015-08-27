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
	Term = require '../term'

	ExpandingTextArea = require('../expandingTextArea').load(win)
	{FaIcon, renderName, showWhen} = require('../utils').load(win)
	{TimestampFormat} = require '../persist/utils'

	EventTabView = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]
		getInitialState: ->
			return {
				title: ''
				description: ''

				startDate: ''
				startTime: ''
				endDate: ''
				endTime: ''

				isDateSpan: false
				usesTimeOfDay: false
			}

		componentDidUpdate: ->
			# Initialize datepickers, update @state when value changes

			$(@refs.startDate.getDOMNode()).datetimepicker({
				useCurrent: false
				format: 'Do MMM, \'YY'
				widgetPositioning: {
					horizontal: 'right'
				}
			}).on 'dp.change', (thisInput) =>
				@setState {startDate: thisInput.date}

			$(@refs.startTime.getDOMNode()).datetimepicker({
				useCurrent: false
				format: 'hh:mm a'
				widgetPositioning: {					
					horizontal: 'right'
				}
			}).on 'dp.change', (thisInput) =>
				@setState {startTime: thisInput.date}


			$(@refs.endDate.getDOMNode()).datetimepicker({
				useCurrent: false
				format: 'Do MMM, \'YY'
				widgetPositioning: {					
					horizontal: 'right'
				}
			}).on 'dp.change', (thisInput) =>
				@setState {endDate: thisInput.date}

			$(@refs.endTime.getDOMNode()).datetimepicker({
				useCurrent: false
				format: 'hh:mm a'
				widgetPositioning: {					
					horizontal: 'right'
				}
			}).on 'dp.change', (thisInput) =>
				@setState {endTime: thisInput.date}	

		render: ->
			return R.div({
				className: "eventView #{showWhen @props.isBeingEdited or not @props.editMode}"
			},
				R.form({className: showWhen @props.isBeingEdited},
					R.span({
						className: 'btn btn-danger'
						onClick: @_closeForm
					}, 
						FaIcon('times')
					)
					R.div({className: 'form-group'},
						R.label({}, "Name")
						R.input({
							value: @state.title
							onChange: @_updateTitle
							placeholder: "Name of #{Term 'event'}"
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "Description")
						ExpandingTextArea({
							value: @state.description
							onChange: @_updateDescription
							placeholder: "Explain details of #{Term 'event'}"
						})
					)
					R.div({className: "dateGroup"},
						R.div({className: 'form-group date'},
							R.label({}, if @state.isDateSpan then "Start Date" else "Date")
							R.input({
								ref: 'startDate'
								className: 'form-control'
								type: 'text'
								placeholder: "Select date"
							})
						)
						R.div({className: "form-group timeOfDay #{showWhen @state.usesTimeOfDay}"},
							R.label({},
								R.span({onClick: @_toggleUsesTimeOfDay},
									FaIcon('clock-o')
									FaIcon('times')
								)
							)
							R.input({
								ref: 'startTime'
								className: 'form-control'
								type: 'text'
								placeholder: "00:00 --"
							})						
						)
						R.div({className: "form-group useTimeOfDay #{showWhen not @state.usesTimeOfDay}"}
							R.button({
								className: 'btn btn-default'									
								onClick: @_toggleUsesTimeOfDay
							}, FaIcon('clock-o'))
						)
					)					
					R.div({className: "dateGroup #{showWhen @state.isDateSpan}"},
						R.div({
							className: 'form-group removeDateSpan'							
						}
							R.span({onClick: @_toggleIsDateSpan},
								FaIcon('arrow-right')
								FaIcon('times')
							)							
						)
						R.div({className: 'form-group date'},
							R.label({}, "End Date")
							R.input({
								ref: 'endDate'
								className: 'form-control'
								type: 'text'
								placeholder: "Select date"
							})
						)
						R.div({className: "form-group timeOfDay #{showWhen @state.usesTimeOfDay}"},
							R.label({},
								R.span({onClick: @_toggleUsesTimeOfDay},
									FaIcon('clock-o')
									FaIcon('times')
								)
							)
							R.input({
								ref: 'endTime'
								className: 'form-control'
								type: 'text'
								placeholder: "00:00 --"
							})						
						)
						R.div({className: "form-group useTimeOfDay #{showWhen not @state.usesTimeOfDay}"}
							R.button({
								className: 'btn btn-default'
								onClick: @_toggleUsesTimeOfDay
							}, FaIcon('clock-o'))
						)
					)
					R.button({
						className: "btn btn-default"
						onClick: @_toggleIsDateSpan
					}, 
						unless @state.isDateSpan
							"Insert End Date"
						else
							"Remove End Date"
					)
					R.button({
						className: 'btn btn-success'
						type: 'submit'
						onClick: @_saveEventData
						disabled: not @state.title or not @state.startDate or (@state.isDateSpan and not @state.endDate) or (@state.usesTimeOfDay and not @state.startTime) or (@state.usesTimeOfDay and not @state.endTime)
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

		_toggleUsesTimeOfDay: (event) ->
			event.preventDefault()
			@setState {usesTimeOfDay: not @state.usesTimeOfDay}, =>
				# Focus timeInput if enabling
				# if @state.usesTimeOfDay
				# 	@refs[timeInput].getDOMNode().focus()

		_showTimestamp: (timestamp) ->
			moment = Moment(timestamp, TimestampFormat)

			if moment.isValid
				return Moment(moment, TimestampFormat).format('YYYY-MM-DD HH:mm')
			else
				return "Invalid Moment"

		_toggleIsDateSpan: (event) ->
			event.preventDefault()
			@setState {isDateSpan: not @state.isDateSpan}, =>
				# Focus endDate if enabling
				if @state.isDateSpan
					@refs.endDate.getDOMNode().focus()

		_updateTitle: (event) ->
			@setState {title: event.target.value}

		_updateDescription: (event) ->
			@setState {description: event.target.value}

		_closeForm: (event) ->
			event.preventDefault()

			if (@state.startDate or @state.endDate or @state.description)
				Bootbox.confirm "Cancel #{Term 'event'} editing?", (result) =>
					if result
						# Make sure all states are reset, then cancel
						@replaceState @props.data, =>
							@props.cancel @props.atIndex
			else
				@replaceState @props.data, =>
					@props.cancel @props.atIndex

		_compiledFormData: ->
			# Days to start and end of day
			startTimestamp = @state.startDate.startOf('day')
			endTimestamp = @state.endDate.endOf('day')

			if @state.usesTimeOfDay
				startTimestamp = startTimestamp.set('hour', @state.startTime.hour()).set('minute', @state.startTime.minute())
				endTimestamp = startTimestamp.set('hour', @state.endTime.hour()).set('minute', @state.endTime.minute())

			return {
				title: @state.title
				description: @state.description
				startTimestamp: startTimestamp.format(TimestampFormat)
				endTimestamp: if @state.isDateSpan then endTimestamp.format(TimestampFormat) else ''
			}				

		_saveEventData: (event) ->
			event.preventDefault()

			newData = @_compiledFormData()

			@props.save newData, @props.atIndex

	return EventTabView

module.exports = {load}