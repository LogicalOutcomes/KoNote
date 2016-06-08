# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

Imm = require 'immutable'
Term = require './term'
{diffChars} = require 'diff'

load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	MetricWidget = require('./metricWidget').load(win)

	{FaIcon, renderLineBreaks, showWhen,
	stripMetadata, formatTimestamp, capitalize} = require('./utils').load(win)

	RevisionHistory = React.createFactory React.createClass
		displayName: 'RevisionHistory'
		mixins: [React.addons.PureRenderMixin]

		getDefaultProps: -> {
			terms: {}
			metricsById: Imm.List()
			disableSnapshot: false
		}

		propTypes: -> {
			dataModelName: React.PropTypes.string()
			revisions: React.PropTypes.instanceOf Imm.List
		}

		_diffStrings: (oldString, newString) ->
			diffs = diffChars(oldString, newString)
			diffedString = ""

			# Vanilla JS for sake of performance
			for diff in diffs
				diffedString += (
					if diff.added?
						"<span class='added'>#{diff.value}</span>"
					else if diff.removed?
						"<span class='removed'>#{diff.value}</span>"
					else
						diff.value
				)

			return diffedString

		_generateChangeLogEntries: (revision, index) ->
			changeLog = Imm.List()

			# Convenience method for adding Imm changeLog entries
			# Replace property name with term from @props when valid
			pushToChangeLog = (entry) =>
				if @props.terms[entry.property]?
					entry.property = @props.terms[entry.property]
				changeLog = changeLog.push Imm.fromJS(entry)

			# Return creation change if 0-index, check existence to make sure
			unless index > 0 and @props.revisions.reverse().get(index - 1)?
				pushToChangeLog {
					property: @props.dataModelName
					action: 'created'
				}

				return changeLog


			# Not a first revision, so let's build the diff objects for each property/value
			# compared to the previous revision (ignoring metadata properties)
			previousRevision = stripMetadata @props.revisions.reverse().get(index - 1)
			currentRevision = stripMetadata revision

			console.log "previousRevision", previousRevision.toJS()
			console.log "currentRevision", currentRevision.toJS()

			currentRevision.entrySeq().forEach ([property, value]) =>
				# Ignore statusReason property, it can't be revised
				return if property is 'statusReason'
				# Account for previousRevision not having this property
				previousValue = previousRevision.get(property) or ""

				# Plain string & number comparison
				if typeof value in ['string', 'number'] and value isnt previousValue
					# Unique handling for 'status'
					if property is 'status' and currentRevision.has('statusReason')
						pushToChangeLog {
							property
							action: value
							value
							reason: currentRevision.get('statusReason')
						}
					else
						pushToChangeLog {
							property
							action: 'revised'
							value
						}

				# Imm List comparison (we assume existence of isList validates Imm.List)
				else if not Imm.is value, previousValue
					console.log "previousValue:", previousValue.toJS()

					switch @props.type
						when 'planTarget'
							# Generate 'removed' list items
							previousValue
							.filterNot (arrayItem) -> value.contains(arrayItem)
							.forEach (arrayItem) -> pushToChangeLog {
								property
								action: 'removed'
								value: arrayItem
							}
							# Generate 'added' list items
							value
							.filterNot (arrayItem) -> previousValue.contains(arrayItem)
							.forEach (arrayItem) -> pushToChangeLog {
								property
								action: 'added'
								value: arrayItem
							}
						when 'progNote'
							value.forEach (unit, unitIndex) =>
								console.info "Unit:", unit.toJS()

								if unit.has 'sections' # 'plan' progNote unit
									console.info "Unit HAS sections:"
									unit.get('sections').forEach (section, sectionIndex) =>
										console.log "Section:", section.toJS()
										section.get('targets').forEach (target, targetIndex) =>
											console.log "Target", target.toJS()
											target.entrySeq().forEach ([targetProperty, targetValue]) =>
												# Grab the same target value from prev revision
												previousTargetValue = previousValue.getIn [
													unitIndex
													'sections', sectionIndex
													'targets', targetIndex, targetProperty
												]
												console.log "Property: #{targetProperty}"
												console.log "targetValue", targetValue
												console.log "previousTargetValue", previousTargetValue
												# Handle regular values
												if typeof targetValue in ['string', 'number'] and targetValue isnt previousTargetValue
													pushToChangeLog {
														parent: target.get('name')
														property: targetProperty
														action: 'revised'
														value: @_diffStrings(previousTargetValue, targetValue)
													}
												# Is it an Imm list? (metrics)
												else if not Imm.is targetValue, previousTargetValue
													console.log "Need to iterate over list:", targetValue

												console.log "----------------------"

								else # 'basic' progNote unit
									console.info "Unit doesn't have section"
									unit.entrySeq().forEach ([unitProperty, unitValue]) =>
										previousUnitValue = previousValue.get(unitIndex)

										console.log "previousUnitValue", previousUnitValue

										# # Handle regular values
										# if typeof unitValue in ['string', 'number'] and unitValue isnt previousUnitValue
										# 	pushToChangeLog {
										# 		property: unitProperty
										# 		action: 'revised'
										# 		value: @_diffStrings(previousUnitValue, unitValue)
										# 	}
										# # Is it an Imm list? (metrics)
										# else if not Imm.is unitValue, previousUnitValue
										# 	console.log "Need to iterate over list:", unitValue

										# console.log "----------------------"

						else
							throw new Error "Unknown RevisionHistory 'type': #{@props.type}"

					console.log "previousValue", previousValue.toJS()
					console.log "value", value.toJS()

					console.log "Change Log:", changeLog.toJS()

					# # Generate 'removed' list items
					# previousValue
					# .filterNot (arrayItem) -> value.contains(arrayItem)
					# .forEach (arrayItem) -> pushToChangeLog {
					# 	property
					# 	action: 'removed'
					# 	value: arrayItem
					# }
					# # Generate 'added' list items
					# value
					# .filterNot (arrayItem) -> previousValue.contains(arrayItem)
					# .forEach (arrayItem) -> pushToChangeLog {
					# 	property
					# 	action: 'added'
					# 	value: arrayItem
					# }

			# Fin.
			return changeLog

		_buildInChangeLog: (revision, index) ->
			changeLog = @_generateChangeLogEntries revision, index
			return revision.set 'changeLog', changeLog

		render: ->
			# Process revision history to devise change logs
			# They're already in reverse-order, so reverse() to map changes
			revisions = @props.revisions
			.reverse()
			.map(@_buildInChangeLog)
			.reverse()

			return R.div({className: 'revisionHistory'},
				R.div({className: 'heading'},
					R.h3({}, "Revision History")
				)

				(if revisions.isEmpty()
					R.div({className: 'noRevisions'},
						"This #{@props.dataModelName} is new.  ",
						"It won't have any history until the #{Term 'client file'} is saved."
					)
				else
					R.div({className: 'revisions'},
						revisions.map (revision, index) => RevisionChangeLog({
							key: revision.get('revisionId')
							isFirstRevision: index is (revisions.size - 1)
							revision
							metricsById: @props.metricsById
							dataModelName: @props.dataModelName
							disableSnapshot: @props.disableSnapshot
						})
					)
				)
			)

	RevisionChangeLog = React.createFactory React.createClass
		displayName: 'RevisionChangeLog'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: -> {
			isSnapshotVisible: null
		}

		_toggleSnapshot: -> @setState {isSnapshotVisible: not @state.isSnapshotVisible}

		render: ->
			revision = @props.revision
			changeLog = revision.get('changeLog')

			console.log "changeLog", changeLog.toJS()

			return R.section({className: 'revision'},
				R.div({className: 'header'},
					R.div({className: 'author'},
						FaIcon('user')
						revision.get('author')
					)
					R.div({className: 'timestamp'},
						if @props.isFirstRevision and revision.get('backdate')
							"#{formatTimestamp revision.get('backdate')} (late entry)"
						else
							formatTimestamp revision.get('timestamp')
					)
				)
				R.div({className: 'changeLog'},
					(changeLog.map (entry, index) =>
						ChangeLogEntry({
							key: index
							index
							entry
							revision
							dataModelName: @props.dataModelName
							metricsById: @props.metricsById
							onToggleSnapshot: @_toggleSnapshot
							isSnapshotVisible: @state.isSnapshotVisible
							disableSnapshot: @props.disableSnapshot
						})
					)
					(if @state.isSnapshotVisible and not @props.disableSnapshot
						RevisionSnapshot({
							revision
							metricsById: @props.metricsById
							isAnimated: true
						})
					)
				)
			)

	ChangeLogEntry = React.createFactory React.createClass
		displayName: 'ChangeLogEntry'
		mixins: [React.addons.PureRenderMixin]

		render: ->
			entry = @props.entry

			console.log "entry", entry.toJS()

			# Account for terminology metricIds -> metrics
			if entry.get('property') is 'metricIds'
				entry = entry.set('property', 'metric')

			R.article({className: 'entry', key: @props.index},
				# Only show snapshotButton on first changeLogEntry
				(if not @props.disableSnapshot and @props.index is 0 and entry.get('action') isnt 'created'
					R.button({
						className: 'btn btn-default btn-xs snapshotButton'
						onClick: @props.onToggleSnapshot
					},
						if not @props.isSnapshotVisible then "view" else "hide"
						" full revision"
					)
				)

				FaIcon(entry.get('icon'))

				R.span({className: 'action'},
					# Different display cases for indication of change
					(if entry.get('action') is 'created'
						"#{capitalize entry.get('action')} #{entry.get('property')}
						#{if not @props.disableSnapshot then ' as: ' else ''}"
					else if entry.has('reason')
						"#{capitalize entry.get('value')} #{@props.dataModelName} because: "
					else if entry.has('parent')
						"#{capitalize entry.get('action')} #{entry.get('property')} for #{entry.get('parent')}: "
					else
						"#{capitalize entry.get('action')} #{entry.get('property')}: "
					)
				)

				(if entry.get('action') is 'created' and not @props.disableSnapshot
					# We can show full snapshot for dataModel creation
					RevisionSnapshot({
						revision: @props.revision
						dataModelName: @props.dataModelName
						metricsById: @props.metricsById
					})
				else if entry.get('property') is 'metric'
					# Use widget to display metric
					metric = @props.metricsById.get(entry.get('value'))

					MetricWidget({
						isEditable: false
						name: metric.get('name')
						definition: metric.get('definition')
						tooltipViewport: '.entry'
						styleClass: 'clear'
					})
				else
					# Set HTML because diffing <span>'s may exist
					__html = entry.get('reason') or entry.get('value')

					R.div({
						className: 'value'
						dangerouslySetInnerHTML: {__html}
					})
				)
			)

	RevisionSnapshot = ({revision, metricsById, isAnimated}) ->
		hasMetrics = revision.get('metricIds')?

		R.div({
			className: [
				'snapshot'
				'animated fadeInDown' if isAnimated
			].join ' '
		},
			R.div({className: 'name'},
				revision.get('name')
			)

			R.div({className: 'description'},
				renderLineBreaks revision.get('description')
			)

			(if hasMetrics
				R.div({className: 'metrics'},
					(revision.get('metricIds').map (metricId) =>
						metric = metricsById.get(metricId)

						MetricWidget({
							isEditable: false
							key: metricId
							name: metric.get('name')
							definition: metric.get('definition')
							tooltipViewport: '.snapshot'
						})
					)
				)
			)
		)

	return RevisionHistory

module.exports = {load}