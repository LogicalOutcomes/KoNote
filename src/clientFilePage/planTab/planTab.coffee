# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Top-level container for Plan Tab and plan-related utlities in the client file
# It holds a transient state of the plan & target definitions, which accept updates from props (db)

Async = require 'async'
Imm = require 'immutable'
_ = require 'underscore'

Config = require '../../config'
Term = require '../../term'
Persist = require '../../persist'


load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	PlanView = require('./planView').load(win)
	RevisionHistory = require('../../revisionHistory').load(win)
	CrashHandler = require('../../crashHandler').load(win)
	OpenDialogLink = require('../../openDialogLink').load(win)
	PrintButton = require('../../printButton').load(win)
	CreatePlanTemplateDialog = require('../createPlanTemplateDialog').load(win)

	{DropdownButton, MenuItem} = require('../../utils/reactBootstrap').load(win, 'DropdownButton', 'MenuItem')
	{FaIcon, showWhen, stripMetadata, scrollToElement} = require('../../utils').load(win)


	PlanTab = React.createFactory React.createClass
		displayName: 'PlanTab'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			currentTargetRevisionsById = @_generateCurrentTargetRevisionsById(@props.planTargetsById)

			return {
				plan: @props.plan # Transient state for plan
				currentTargetRevisionsById
				selectedTargetId: null
				isCollapsedView: false
			}

		componentWillReceiveProps: ({plan, planTargetsById}) ->
			# Regenerate transient plan data & definitions when is updated upstream (db)
			planChanged = not Imm.is(plan, @props.plan)
			planTargetsChanged = not Imm.is(planTargetsById, @props.planTargetsById)
			currentTargetRevisionsById = @_generateCurrentTargetRevisionsById(planTargetsById)

			if planChanged or planTargetsChanged
				@setState {
					plan
					currentTargetRevisionsById
				}

		_generateCurrentTargetRevisionsById: (planTargetsById) ->
			return planTargetsById.mapEntries ([targetId, target]) =>
				latestRev = stripMetadata target.get('revisions').first()
				return [targetId, latestRev]

		render: ->
			{plan, currentTargetRevisionsById} = @state

			# If something selected and that target has not been deleted
			if @state.selectedTargetId? and currentTargetRevisionsById.has(@state.selectedTargetId)
				# If this target has been saved at least once
				if @props.planTargetsById.has @state.selectedTargetId
					selectedTarget = @props.planTargetsById.get @state.selectedTargetId
				else
					# New target with no revision history
					selectedTarget = Imm.fromJS {
						id: @state.selectedTargetId
						revisions: []
					}
			else
				selectedTarget = null

			hasChanges = @hasChanges()
			hasPlanSections = not plan.get('sections').isEmpty()


			return R.div({className: 'planTab'},

				# TODO: Put directly into header
				OpenDialogLink({
					ref: 'planTemplatesButton'
					className: ''
					dialog: CreatePlanTemplateDialog
					title: "Create Template from Plan"
					sections: @state.plan.get('sections')
					currentTargetRevisionsById
				})

				R.div({className: 'leftPane'},

					# TODO: Make component
					R.div({className: "empty #{showWhen not hasPlanSections}"},
						R.div({className: 'message'},
							"This #{Term 'client'} does not currently have any #{Term 'plan targets'}."
						)
						R.button({
							className: 'addSection btn btn-success btn-lg'
							onClick: @_addSection
							disabled: @props.isReadOnly
						},
							FaIcon('plus')
							"Add #{Term 'section'}"
						)
						R.span({className: 'templates'},
							(unless @props.planTemplateHeaders.isEmpty()
								DropdownButton({
									className: 'btn btn-lg'
									title: "Apply #{Term 'Template'}"
									disabled: @props.isReadOnly
								},
									(@props.planTemplateHeaders.map (planTemplateHeader) =>
										MenuItem({
											key: planTemplateHeader.get('id')
											onClick: @_applyPlanTemplate.bind null, planTemplateHeader.get('id')
										},
											planTemplateHeader.get('name')
										)
									)
								)
							)
						)
					)

					# TODO: Make component
					R.div({className: "flexButtonToolbar #{showWhen plan.get('sections').size > 0}"},

						R.button({
							className: 'saveButton'
							disabled: @props.isReadOnly or not hasChanges
							onClick: @_save
						},
							FaIcon('save', {className:'menuItemIcon'})
							R.span({className: 'menuItemText'},
								"Save"
							)
						)

						R.button({
							className: 'discardButton'
							disabled: @props.isReadOnly or not hasChanges
							onClick: @_resetChanges
						},
							FaIcon('undo', {className:'menuItemIcon'})
							R.span({className: 'menuItemText'},
								"Discard"
							)
						)

						R.button({
							className: 'reorderButton'
							onClick: => @_toggleCollapsedView()
						},
							(if @state.isCollapsedView
								R.div({},
									FaIcon('expand', {className:'menuItemIcon'})
									R.span({className: 'menuItemText'},
										" Expand"
									)
								)
							else
								R.div({},
									FaIcon('compress', {className:'menuItemIcon'})
									R.span({className: 'menuItemText'},
										"Collapse"
									)
								)
							)
						)

						PrintButton({
							dataSet: [
								{
									format: 'plan'
									data: {
										sections: plan.get('sections')
										targets: currentTargetRevisionsById
										metrics: @props.metricsById
									}
									clientFile: @props.clientFile
								}
							]
							iconOnly: false
							iconClassName: 'menuItemIcon'
							labelClassName: 'menuItemText'
							disabled: hasChanges
						})

						DropdownButton({
							id: 'planTemplatesDropdown'
							key: 'planTemplatesDropdownButton'
							title: R.span({},
								FaIcon('wpforms', {className:'menuItemIcon'})
								R.span({className: 'menuItemText'},
									"Templates"
								)
							)
							disabled: @props.isReadOnly
							noCaret: true
						},

							MenuItem({onClick: @_openCreateTemplateDialog},
								"Create Plan Template"
							)

							(unless @props.planTemplateHeaders.isEmpty()
								[
									MenuItem({divider: true})

									MenuItem({header: true}, R.h5({}, "Apply #{Term 'Template'}"))

									(@props.planTemplateHeaders.map (planTemplateHeader) =>
										MenuItem({
											key: planTemplateHeader.get('id')
											onClick: @_applyPlanTemplate.bind null, planTemplateHeader.get('id')
											disabled: @props.isReadOnly
										},
											planTemplateHeader.get('name')
										)
									)
								]
							)
						)

						R.button({
							className: 'addSectionButton'
							onClick: @_addSection
							disabled: @props.isReadOnly
						},
							FaIcon('plus', {className:'menuItemIcon'})
							R.span({className: 'menuItemText'},
								"#{Term 'Section'}"
							)
						)

					)

					PlanView({
						ref: 'planView'
						clientFile: @props.clientFile
						plan
						metricsById: @props.metricsById
						planTargetsById: @props.planTargetsById
						currentTargetRevisionsById
						selectedTargetId: @state.selectedTargetId

						isReadOnly: @props.isReadOnly
						isCollapsed: @state.isCollapsedView

						renameSection: @_renameSection
						addTargetToSection: @_addTargetToSection
						removeNewTarget: @_removeNewTarget
						removeNewSection: @_removeNewSection
						hasTargetChanged: @_hasTargetChanged
						updateTarget: @_updateTarget
						setSelectedTarget: @_setSelectedTarget
						addMetricToTarget: @_addMetricToTarget
						deleteMetricFromTarget: @_deleteMetricFromTarget
						getSectionIndex: @_getSectionIndex
						collapseAndSelectTargetId: @_collapseAndSelectTargetId

						reorderSection: @_reorderSection
						reorderTargetId: @_reorderTargetId
					})
				)

				R.div({className: 'rightPane targetDetail'},
					(if not selectedTarget?
						R.div({className: "noSelection #{showWhen plan.get('sections').size > 0}"},
							"More information will appear here when you select ",
							"a #{Term 'target'} on the left."
						)
					else
						R.div({className: 'revisionHistoryContainer'},
							RevisionHistory({
								revisions: selectedTarget.get('revisions')
								type: 'planTarget'
								metricsById: @props.metricsById
								programsById: @props.programsById
								dataModelName: 'target'
								terms: {
									metric: Term 'metric'
								}
							})
						)
					)
				)
			)

		blinkUnsaved: ->
			toggleBlink = -> $('.hasChanges').toggleClass('blink')
			secondBlink = ->
				toggleBlink()
				setTimeout(toggleBlink, 500)

			setTimeout(secondBlink, 750)

		hasChanges: ->
			# If there is a difference, then there have been changes
			unless Imm.is @props.plan, @state.plan
				return true

			for targetId in @state.currentTargetRevisionsById.keySeq().toJS()
				if @_hasTargetChanged targetId
					return true

			return false

		_hasTargetChanged: (targetId, currentTargetRevisionsById, planTargetsById) ->
			# Default to retrieving these values from the component
			currentTargetRevisionsById or= @state.currentTargetRevisionsById
			planTargetsById or= @props.planTargetsById

			# Get current revision (normalized) of the specified target
			currentRev = @_normalizeTarget currentTargetRevisionsById.get(targetId)

			# If this is a new target
			target = planTargetsById.get(targetId, null)
			unless target
				# If target is empty
				emptyName = currentRev.get('name') is ''
				emptyDescription = currentRev.get('description') is ''
				if emptyName and emptyDescription
					return false

				return true

			lastRev = target.getIn ['revisions', 0]

			lastRevNormalized = lastRev
				.delete('revisionId')
				.delete('author')
				.delete('timestamp')

			return not Imm.is(currentRev, lastRevNormalized)

		_save: ->
			@_normalizeTargets()
			@_removeUnusedTargets()

			# Wait for state changes to be applied
			@forceUpdate =>
				valid = @_validateTargets()

				unless valid
					Bootbox.alert "Cannot save #{Term 'plan'}: there are empty #{Term 'target'} fields."
					return

				# Capture these values for use in filtering functions below.
				# This is necessary to ensure that they won't change between
				# now and when the filtering functions are actually called.
				currentTargetRevisionsById = @state.currentTargetRevisionsById
				planTargetsById = @props.planTargetsById

				newPlanTargets = currentTargetRevisionsById.valueSeq()
				.filter (target) =>
					# Only include targets that have not been saved yet
					return not planTargetsById.has(target.get('id'))
				.map(@_normalizeTarget)

				updatedPlanTargets = currentTargetRevisionsById.valueSeq()
				.filter (target) =>
					# Ignore new targets
					unless planTargetsById.has(target.get('id'))
						return false

					# Only include targets that have actually changed
					return @_hasTargetChanged(
						target.get('id'),
						currentTargetRevisionsById,
						planTargetsById
					)
				.map(@_normalizeTarget)

				@props.updatePlan @state.plan, newPlanTargets, updatedPlanTargets

		_collapseAndSelectTargetId: (selectedTargetId, cb) ->
			@setState {
				isCollapsedView: false
				selectedTargetId
			}, cb

		_toggleCollapsedView: ->
			isCollapsedView = not @state.isCollapsedView
			@setState {isCollapsedView}

		_reorderSection: (dragIndex, hoverIndex) ->
			if @props.isReadOnly
				@_showReadOnlyAlert()
				return

			sections = @state.plan.get('sections')
			dragSection = sections.get(dragIndex)

			sections = sections
			.delete(dragIndex)
			.splice(hoverIndex, 0, dragSection)

			plan = @state.plan.set('sections', sections)

			@setState {plan}

		_reorderTargetId: (sectionIndex, dragIndex, hoverIndex) ->
			if @props.isReadOnly
				@_showReadOnlyAlert()
				return

			targetIds = @state.plan.getIn(['sections', sectionIndex, 'targetIds'])
			dragTarget = targetIds.get(dragIndex)

			targetIds = targetIds
			.delete(dragIndex)
			.splice(hoverIndex, 0, dragTarget)

			plan = @state.plan.setIn(['sections', sectionIndex, 'targetIds'], targetIds)

			@setState {plan}

		_showReadOnlyAlert: ->
			Bootbox.alert "Sorry, you can't modify the #{Term 'plan'} while in read-only mode."

		_resetChanges: ->
			Bootbox.confirm "Discard all changes made to the #{Term 'plan'}?", (ok) =>
				if ok
					@setState {
						currentTargetRevisionsById: @_generateCurrentTargetRevisionsById @props.planTargetsById
						plan: @props.plan
					}

		_normalizeTargets: ->
			@setState (state) =>
				return {
					currentTargetRevisionsById: state.currentTargetRevisionsById
					.map (targetRev, targetId) =>
						return @_normalizeTarget targetRev
				}

		_normalizeTarget: (targetRev) ->
			trim = (s) -> s.trim()

			# Trim whitespace from fields
			return targetRev
			.update('name', trim)
			.update('description', trim)

		_removeUnusedTargets: ->
			@setState (state) =>
				unusedTargetIds = state.plan.get('sections').flatMap (section) =>
					return section.get('targetIds').filter (targetId) =>
						currentRev = state.currentTargetRevisionsById.get(targetId)
						emptyName = currentRev.get('name') is ''
						emptyDescription = currentRev.get('description') is ''
						noMetrics = currentRev.get('metricIds').size is 0
						noHistory = @props.planTargetsById.get(targetId, null) is null

						return emptyName and emptyDescription and noMetrics and noHistory

				return {
					plan: state.plan.update 'sections', (sections) =>
						return sections.map (section) =>
							return section.update 'targetIds', (targetIds) =>
								return targetIds.filter (targetId) =>
									return not unusedTargetIds.contains(targetId)

					currentTargetRevisionsById: state.currentTargetRevisionsById
					.filter (rev, targetId) =>
						return not unusedTargetIds.contains(targetId)
				}

		_validateTargets: -> # returns true iff all valid
			return @state.plan.get('sections').every (section) =>
				return section.get('targetIds').every (targetId) =>
					currentRev = @state.currentTargetRevisionsById.get(targetId)

					emptyName = currentRev.get('name') is ''
					emptyDescription = currentRev.get('description') is ''

					return not emptyName and not emptyDescription

		_addSection: ->
			sectionId = Persist.generateId()

			Bootbox.prompt "Enter a name for the new #{Term 'section'}:", (sectionName) =>
				sectionName = sectionName?.trim()

				unless sectionName
					return

				newPlan = @state.plan.update 'sections', (sections) =>
					return sections.push Imm.fromJS {
						id: sectionId
						name: sectionName
						targetIds: []
						status: 'default'
					}

				@setState {plan: newPlan}, =>
					@_addTargetToSection sectionId

		_openCreateTemplateDialog: (event) ->
			@refs.planTemplatesButton.open(event)

		_applyPlanTemplate: (templateId) ->
			Bootbox.confirm "Are you sure you want to apply this template?", (ok) =>
				if ok
					clientFileHeaders = null
					selectedPlanTemplate = null
					templateSections = null
					existsElsewhere = null
					newCurrentRevs = null
					newPlan = null
					targetIds = Imm.List()
					clientFileId = @props.clientFileId

					Async.series [

						(cb) =>
							ActiveSession.persist.planTemplates.readLatestRevisions templateId, 1, (err, result) ->
								if err
									cb err
									return

								selectedPlanTemplate = stripMetadata result.get(0)
								cb()

						(cb) =>
							newCurrentRevs = @state.currentTargetRevisionsById
							templateSections = selectedPlanTemplate.get('sections').map (templateSection) =>
								targetIds = Imm.List()
								templateSection.get('targets').forEach (target) =>
									target.get('metricIds').forEach (metricId) =>

										# Metric exists in another target
										existsElsewhere = @state.currentTargetRevisionsById.some (target) =>
											return target.get('metricIds').contains(metricId)
										if existsElsewhere
											return

									targetId = '__transient__' + Persist.generateId()
									targetIds = targetIds.push targetId

									newTarget = Imm.fromJS {
										id: targetId
										clientFileId
										name: target.get('name')
										description: target.get('description')
										status: 'default'
										metricIds: target.get('metricIds')
									}

									newCurrentRevs = newCurrentRevs.set targetId, newTarget

								section = templateSection.set 'status', 'default'
								.set 'targetIds', targetIds
								.set 'id', Persist.generateId()
								.remove 'targets'

								return section

							if existsElsewhere
								cb('CANCEL')
								return
							cb()

						(cb) =>

							newPlan = @state.plan.update 'sections', (sections) =>
								return sections.concat(templateSections)

							@setState {
								plan: newPlan
								currentTargetRevisionsById: newCurrentRevs
							}

							cb()

					], (err) =>
						if err
							if err is 'CANCEL'
								Bootbox.alert "A #{Term 'metric'} in this template already exists for another #{Term 'plan target'}"
								return

							if err instanceof Persist.IOError
								console.error err
								Bootbox.alert """
									Please check your network connection and try again.
								"""
								return

							CrashHandler.handle err
							return
					return

		_renameSection: (sectionId) ->
			sectionIndex = @_getSectionIndex sectionId
			sectionName = @state.plan.getIn ['sections', sectionIndex, 'name']

			Bootbox.prompt {
				title: "Rename #{Term 'section'}:"
				value: sectionName
				callback: (newSectionName) =>
					newSectionName = newSectionName?.trim()

					unless newSectionName
						return

					newPlan = @state.plan.setIn ['sections', sectionIndex, 'name'], newSectionName
					@setState {plan: newPlan}
			}

		_addTargetToSection: (sectionId) ->
			sectionIndex = @_getSectionIndex sectionId

			targetId = '__transient__' + Persist.generateId()
			newPlan = @state.plan.updateIn ['sections', sectionIndex, 'targetIds'], (targetIds) =>
				return targetIds.push targetId

			newTarget = Imm.fromJS {
				id: targetId
				clientFileId: @props.clientFileId
				status: 'default'
				name: ''
				description: ''
				metricIds: []
			}
			newCurrentRevs = @state.currentTargetRevisionsById.set targetId, newTarget

			@setState {
				plan: newPlan
				currentTargetRevisionsById: newCurrentRevs
			}, =>
				# Temporary until we work out a Bootbox alternative
				setTimeout(=>
					$(".target-#{targetId} .name.field").focus()
				, 250)

		_removeNewTarget: (sectionId, transientTargetId) ->
			sectionIndex = @_getSectionIndex sectionId

			plan = @state.plan.updateIn ['sections', sectionIndex, 'targetIds'], (targetIds) =>
				targetIndex = targetIds.indexOf transientTargetId
				return targetIds.splice(targetIndex, 1)

			currentTargetRevisionsById = @state.currentTargetRevisionsById.delete transientTargetId

			@setState {plan, currentTargetRevisionsById}

		_removeNewSection: (section) ->
			sectionId = section.get('id')
			sectionIndex = @_getSectionIndex sectionId

			# Update plan
			plan = @state.plan.set 'sections', @state.plan.get('sections').splice(sectionIndex, 1)

			# Filter out all this section's targetIds from currentTargetRevisionsById
			currentTargetRevisionsById = @state.currentTargetRevisionsById.filterNot (targetRevision, targetId) ->
				section.get('targetIds').contains targetId

			@setState {plan, currentTargetRevisionsById}

		_getSectionIndex: (sectionId) ->
			return @state.plan.get('sections').findIndex (section) =>
				return section.get('id') is sectionId

		_updateTarget: (targetId, newValue) ->
			@setState {
				currentTargetRevisionsById: @state.currentTargetRevisionsById.set targetId, newValue
			}

		_setSelectedTarget: (targetId, cb) ->
			# Prevent event obj arg from ftn binds in planTarget
			cb = (->) unless typeof cb is 'function'

			@setState {selectedTargetId: targetId}, cb

		_addMetricToTarget: (targetId, cb, metricId) ->
			targetRevision = @state.currentTargetRevisionsById.get(targetId)

			if not targetRevision
				throw new Error "Target ID #{targetID} does not exist in @state.currentTargetRevisionsById"
				return

			# Current target already has this metric
			if targetRevision.get('metricIds').contains metricId
				Bootbox.alert "This #{Term 'metric'} has already been added to the selected #{Term 'target'}."
				return

			# Metric exists in another target
			existsElsewhere = @state.currentTargetRevisionsById.some (target) =>
				return target.get('metricIds').contains(metricId)
			if existsElsewhere
				Bootbox.alert "This #{Term 'metric'} already exists for another #{Term 'plan target'}"
				return

			@setState {
				currentTargetRevisionsById: @state.currentTargetRevisionsById.update targetId, (currentRev) ->
					return currentRev.update 'metricIds', (metricIds) ->
						return metricIds.push metricId
			}, cb

		_deleteMetricFromTarget: (targetId, metricId) ->
			@setState {
				currentTargetRevisionsById: @state.currentTargetRevisionsById.update targetId, (currentRev) ->
					return currentRev.update 'metricIds', (metricIds) ->
						return metricIds.filter (id) ->
							return id isnt metricId
			}


	return PlanTab

module.exports = {load}