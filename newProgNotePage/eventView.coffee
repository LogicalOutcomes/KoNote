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
			return if not _.isEmpty(@props.data) then @props.data else {}

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
				className: "info #{showWhen @props.isBeingEdited or not @props.editMode}"
			},
				R.form({className: showWhen @props.isBeingEdited},
					R.button({
						className: 'btn btn-danger'
						onClick: @_closeForm
					}, FaIcon('times'))
					R.button({
						className: 'btn btn-warning'
						onClick: @_toggleHasDateSpan
					}, "Date Span")
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
					R.input({
						type: 'text'
						ref: 'startTimestamp'
						className: 'form-control'
					})
					R.input({
						type: 'text'
						ref: 'endTimestamp'
						className: "form-control #{showWhen not @state.hasDateSpan}"
					})
					R.button({
						className: 'btn btn-success'
						onClick: @_saveEventData
						disabled: not @state.title or not @state.startTimestamp or (@state.hasDateSpan and not @state.endTimestamp)
					}, 
						"Save"
						FaIcon('check')
					)
				)
				(unless @props.isBeingEdited
					R.div({className: "details"},
						startTimestamp = Moment(@props.data.startTimestamp, TimestampFormat).format('YYYY-MM-DD')
						endTimestamp = Moment(@props.data.endTimestamp, TimestampFormat).format('YYYY-MM-DD')

						"title: #{@props.data.title}\n"
						"description: #{@props.data.description}\n"
						"startTimestamp: #{startTimestamp}\n"
						"endTimestamp: #{endTimestamp}\n"						
					)
				)				
			)

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
				endTimestamp: if @state.isSpanned then @state.endTimestamp else ''
				description: @state.description
			}				

		_saveEventData: (event) ->
			event.preventDefault()

			newData = @_compiledFormData()

			@props.save newData, @props.atIndex

	return EventTabView

module.exports = {load}