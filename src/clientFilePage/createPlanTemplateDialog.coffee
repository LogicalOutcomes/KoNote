# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Dialog for creating a new plan template from the provided plan section(s)

Imm = require 'immutable'

Persist = require '../persist'


load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	CrashHandler = require('../crashHandler').load(win)
	Dialog = require('../dialog').load(win)


	CreatePlanTemplateDialog = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]
		# TODO: propTypes

		componentDidMount: ->
			@refs.templateNameField.focus()

		getInitialState: -> {
			templateName: ''
		}

		render: ->
			Dialog({
				ref: 'dialog'
				title: @props.title
				onClose: @props.onClose
			},
				R.div({className: 'createPlanTemplateDialog'},
					R.div({className: 'form-group'},
						R.label({}, "Template Name"),
						R.input({
							className: 'form-control'
							ref: 'templateNameField'
							onChange: @_updateTemplateName
							value: @state.templateName
							placeholder: "Template Name"
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "Template Description"),
						R.textarea({
							className: 'form-control'
							style: {minWidth: 350, minHeight: 100}
							ref: 'statusReasonField'
							onChange: @_updateTemplateDescription
							value: @state.templateDescription
							placeholder: "Template Description"
						})
					)
					R.div({className: 'btn-toolbar'},
						R.button({
							className: 'btn btn-default'
							onClick: @props.onCancel
						}, "Cancel")
						R.button({
							className: 'btn btn-primary'
							onClick: @_submit
							disabled: not @state.templateName or not @state.templateDescription
						}, "Confirm")
					)
				)
			)

		_updateTemplateName: (event) ->
			@setState {templateName: event.target.value}

		_updateTemplateDescription: (event) ->
			@setState {templateDescription: event.target.value}

		_submit: ->
			templateSections = @props.sections.map (section) =>
				sectionTargets = section.get('targetIds').map (targetId) =>
					target = @props.currentTargetRevisionsById.get(targetId)
					# Removing irrelevant data from object
					return target
					.remove('status')
					.remove('statusReason')
					.remove('clientFileId')
					.remove('id')
					.remove('authorDisplayName')

				section = Imm.fromJS {
					name: section.get('name')
					targets: sectionTargets
				}

			planTemplate = Imm.fromJS {
				name: @state.templateName
				description: @state.templateDescription
				status: 'default'
				sections: templateSections
			}

			global.ActiveSession.persist.planTemplates.create planTemplate, (err, obj) =>
				if err
					if err instanceof Persist.IOError
						console.error err
						Bootbox.alert """
							Please check your network connection and try again
						"""
						return

					CrashHandler.handle(err)
					return

				Bootbox.alert "New template: '#{@state.templateName}' created."
				@props.onSuccess()


	return CreatePlanTemplateDialog

module.exports = {load}
