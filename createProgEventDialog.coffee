# A dialog for allowing the user to create a new client file

Persist = require './persist'
Imm = require 'immutable'
Moment = require 'moment'

load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	Dialog = require('./dialog').load(win)
	LayeredComponentMixin = require('./layeredComponentMixin').load(win)
	Spinner = require('./spinner').load(win)	

	CreateProgEventDialog = React.createFactory React.createClass
		getInitialState: ->
			return {
				title: ''
				description: ''
				dateSpan: false
				startDate: ''
				endDate: ''
				isOpen: true
			}
		render: ->
			Dialog({
				title: "Create Event"
				onClose: @props.onClose
			},
				R.div({className: 'createEventDialog'},
					R.div({className: 'form-group'},
						R.label({}, "Short title"),
						R.input({
							className: 'form-control'
							onChange: @_updateTitle
							value: @state.title
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "Describe the event"),
						R.input({
							className: 'form-control'
							onChange: @_updateDescription
							value: @state.description
							placeholder: "(optional)"
						})
					)
					R.div({className: 'checkbox'},
						R.label({},
							R.input({
								type: 'checkbox'
								onChange: @_updateDateSpan
								checked: @state.DateSpan
							}), "Occured over multiple days"
						)						
					)
					R.div({className: 'form-group'},
						R.label({}, if @state.dateSpan then "Began" else "Date")
						R.input({
							type: 'date'
							onChange: @_updateStartDate
						})
					)
					R.div({className: [
						'form-group'
						if @state.dateSpan then 'show' else 'hidden'
						].join(' ')
					},
						R.label({}, "Ended")
						R.input({
							type: 'date'
							onChange: @_updateEndDate
						})
					)
					# # TODO - Event Categories
					# R.div({className: 'form-group'},
					# 	R.label({}, "Category"),
					# 	R.select({
					# 		className: 'form-control'
					# 		onChange: @_updateCategory
					# 		defaultValue: "- Select Category -"
					# 	},
					# 		R.option({
					# 			value: 'option1'
					# 		}, "Option 1")
					# 	)
					# )
					R.div({className: 'btn-toolbar'},
						R.button({
							className: 'btn btn-default'
							onClick: @_cancel							
						}, "Cancel")
						R.button({
							className: 'btn btn-primary'
							onClick: @_submit
							disabled: not @state.title or not @state.startDate or (@state.dateSpan and not @state.endDate)
						}, "Create Event")
					)
				)
			)
		_cancel: ->
			@props.onCancel()
		_updateTitle: (event) ->
			@setState {title: event.target.value}
		_updateDescription: (event) ->
			@setState {description: event.target.value}
		_updateDateSpan: (event) ->
			@setState (dateSpan: event.target.checked)
		_updateStartDate: (event) ->
			@setState {startDate: event.target.value}
		_updateEndDate: (event) ->
			@setState {endDate: event.target.value}
		_submit: ->

			title = @state.title
			description = @state.description
			startDate = @state.startDate
			endDate = @state.endDate

			@setState {isLoading: true}

			progEvent = Imm.fromJS {
			  title: title
			  description: description
			  startDate: Moment(startDate, 'YYYY-MM-DD').format('YYYYMMDD')
			  endDate: Moment(endDate, 'YYYY-MM-DD').format('YYYYMMDD') if @state.dateSpan
			}

			Bootbox.alert
				title: "Success!"
				message: "New event created!"
				callback: =>
					@props.onSuccess(progEvent)
			
			# global.ActiveSession.persist.progEvents.create progEvent, (err, obj) =>
			# 	@setState {isLoading: false}

			# 	if err
			# 		# TODO: Logic to check for pre-existing client file
			# 		# if err instanceof Persist.Users.UserNameTakenError
			# 		# 	Bootbox.alert "That user name is already taken."
			# 		# 	return

			# 		console.error err.stack
			# 		Bootbox.alert "An error occurred while creating the account"
			# 		return

			# 	console.log("Progress Event created:", obj.get('id'))

			# 	Bootbox.alert
			# 		message: "New event created"
			# 		callback: =>
			# 			@props.onSuccess(obj.get('id'))

	return CreateProgEventDialog

module.exports = {load}
