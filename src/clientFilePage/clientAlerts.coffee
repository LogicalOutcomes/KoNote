# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# PROTOTYPE FEATURE

# We assume for now there will only be 1 alert, as a simple textarea (content),
# which is initially created, and updated.

# As a full feature, this will be an itemized list of individual alerts,
# so the dataModel is modelled on that eventuality.


Imm = require 'immutable'
Moment = require 'moment'
Async = require 'async'

Persist = require '../persist'


load = (win) ->
	React = win.React
	R = React.DOM
	Bootbox = win.bootbox

	CrashHandler = require('../crashHandler').load(win)
	ExpandingTextArea = require('../expandingTextArea').load(win)
	WithTooltip = require('../withTooltip').load(win)

	{FaIcon, renderLineBreaks} = require('../utils').load(win)


	ClientAlerts = React.createFactory React.createClass
		displayName: 'ClientAlerts'
		mixins: [React.addons.PureRenderMixin]

		propTypes: {
			alerts: React.PropTypes.instanceOf(Imm.List).isRequired
			clientFileId: React.PropTypes.string.isRequired
			isDisabled: React.PropTypes.bool.isRequired
		}

		_getSingleAlert: ->
			# We currently assume only 1 alert is in the alerts List(),
			# which is the only one created and updated
			return @props.alerts.first() or Imm.Map()

		getInitialState: ->
			content = @_getSingleAlert().get('content')

			return {
				content: content or ''
				beginTimestamp: Moment()
				isEditing: null
			}

		componentDidUpdate: (newProps) ->
			# Reset component when alert data changes
			# TODO: Account for hasChanges/isEditing
			if not Imm.is newProps.alerts, @props.alerts
				@_reset()

		hasChanges: ->
			originalContent = @_getSingleAlert().get('content') or ''
			return @state.content isnt originalContent

		render: ->
			R.div({
				className: 'clientAlerts animated fadeInUp'
				onClick: @_beginEditing unless @state.isEditing
			},
				R.h3({className: 'animated fadeInUp'},
					# FaIcon('exclamation-triangle')
					# ' '
					"No " unless @state.content
					"Alerts"
				)
				R.div({id: 'alertsContainer'},
					(if @state.isEditing
						R.div({id: 'isEditingContent'},
							ExpandingTextArea({
								ref: 'textarea'
								value: @state.content
								onChange: @_updateContent
							})
							R.div({className: 'btn-toolbar pull-right'},
								R.button({
									className: 'btn btn-sm btn-default'
									onClick: @_cancelEditing
								}, "Cancel")
								R.button({
									className: 'btn btn-sm btn-success'
									disabled: not @hasChanges()
									onClick: @_save
								},
									"Save"
									' '
									FaIcon('check')
								)
							)
						)
					else
						WithTooltip({
							title: "Click here to add/update alerts" if @state.content
							placement: 'right'
							container: 'body'
						},
							R.div({id: 'staticContent'},
								renderLineBreaks(@state.content or "Click here to add an alert")
							)
						)
					)
				)
			)

		_updateContent: (event) ->
			content = event.target.value
			@setState {content}

		_beginEditing: ->
			return if @props.isDisabled

			isEditing = true
			beginTimestamp = Moment()

			@setState {isEditing, beginTimestamp}, =>
				@refs.textarea.focus() if @refs.textarea?

		_cancelEditing: ->
			if @hasChanges()
				Bootbox.confirm "Discard changes to this alert?", (ok) =>
					if ok then @_reset()
			else
				@_reset()

		_reset: ->
			@setState @getInitialState()

		_save: ->
			clientFileId = @props.clientFileId
			content = @state.content

			isExistingAlert = @_getSingleAlert().has('id')

			saveAlert = if isExistingAlert then @_updateAlert else @_createAlert

			saveAlert (err) =>
				if err
					if err instanceof Persist.IOError
						Bootbox.alert """
							An error occurred.  Please check your network connection and try again.
						"""
						return

					CrashHandler.handle err
					return

				# Component state will automatically reset when @props.alerts changes

		_createAlert: (cb) ->
			clientFileId = @props.clientFileId
			content = @state.content
			authorProgramId = ActiveSession.programId or ''

			alert = Imm.fromJS {
				content
				clientFileId
				status: 'default'
				authorProgramId
			}

			createdAlert = null

			Async.series [
				(cb) =>
					Bootbox.prompt "Reason for the new alert (optional)", (updateReason) ->
						if updateReason
							alert = alert.set('updateReason', updateReason)

						cb()

				(cb) =>
					ActiveSession.persist.alerts.create alert, (err, result) ->
						if err
							cb err
							return

						createdAlert = result
						cb()

				(cb) =>
					@_generateQuickNote createdAlert, cb

			], cb

		_updateAlert: (cb) ->
			clientFileId = @props.clientFileId
			content = @state.content
			authorProgramId = ActiveSession.programId or ''

			alert = @_getSingleAlert()
			.set 'clientFileId', clientFileId
			.set 'content', content
			.set 'authorProgramId', authorProgramId
			.remove 'updateReason'

			updatedAlert = null

			Async.series [
				(cb) =>
					Bootbox.prompt "Explanation for the alert update (optional)", (updateReason) ->
						if updateReason
							alert = alert.set('updateReason', updateReason)

						cb()

				(cb) =>
					ActiveSession.persist.alerts.createRevision alert, (err, result) ->
						if err
							cb err
							return

						updatedAlert = result
						cb()

				(cb) =>
					@_generateQuickNote updatedAlert, cb

			], cb

		_generateQuickNote: (alert, cb) ->
			notes = "Alert info changed to: #{alert.get('content')}"

			# Append updateReason to quickNote if exists
			if alert.has('updateReason')
				notes += "\n\n(Reason: #{alert.get('updateReason')})"

			authorProgramId = ActiveSession.programId or ''
			beginTimestamp = @state.beginTimestamp.format(Persist.TimestampFormat)
			clientFileId = @props.clientFileId

			quickNote = Imm.fromJS {
				type: 'basic' # aka "Quick Notes"
				status: 'default'
				notes
				backdate: ''
				authorProgramId
				beginTimestamp
				clientFileId
			}

			ActiveSession.persist.progNotes.create quickNote, cb


	return ClientAlerts


module.exports = {load}