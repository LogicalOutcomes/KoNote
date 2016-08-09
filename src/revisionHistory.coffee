# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

Imm = require 'immutable'
ImmPropTypes = require 'react-immutable-proptypes'
Term = require './term'
{diffSentences, diffWordsWithSpace} = require 'diff'
DiffMatchPatch = require 'diff-match-patch'

load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	MetricWidget = require('./metricWidget').load(win)
	ColorKeyBubble = require('./colorKeyBubble').load(win)

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
			dataModelName: React.PropTypes.string().isRequired()
			revisions: ImmPropTypes.list.isRequired()
			programsById: ImmPropTypes.map.isRequired()
		}

		_diffStrings: (oldString, newString) ->
			dmp = new DiffMatchPatch()
			# first pass; can lower timeout if too slow
			# dmp.Diff_Timeout = 0.5
			diffs = dmp.diff_main(oldString, newString)
			# measure of similarity
			lev = dmp.diff_levenshtein(diffs)
			# second pass
			if lev > 20
				diffs = diffSentences(oldString, newString)
			else
				diffs = diffWordsWithSpace(oldString, newString)

			return R.span({className: 'value'},
				# Iterate over diffs and assign a diff-span or plain string
				for diff, key in diffs
					if diff.added?
						R.span({className: 'added', key}, diff.value)
					else if diff.removed?
						R.span({className: 'removed', key}, diff.value)
					else
						diff.value
			)

		_generateChangeLogEntries: (revision, index) ->
			changeLog = Imm.List()

			# Convenience method for adding Imm changeLog entries
			# Replace property name with term from @props when valid
			pushToChangeLog = (entry) =>
				if @props.terms[entry.property]?
					entry.property = @props.terms[entry.property]
				changeLog = changeLog.push Imm.fromJS(entry)

			# Process the changes of an object or Imm.List from its predecessor
			processChanges = ({parent, property, value, previousValue}) =>
				# Handle regular values
				if typeof value in ['string', 'number'] and value isnt previousValue
					pushToChangeLog {
						parent
						property
						action: 'revised'
						value: @_diffStrings(previousValue, value)
					}
				# Is it an Imm list? (metrics)
				else if property in ['metric', 'metrics']
					# Generate 'revised' (metric value) changes
					value.forEach (arrayItem) =>
						itemId = arrayItem.get('id')
						itemValue = arrayItem.get('value')
						previousItem = previousValue.find (item) -> item.get('id') is itemId
						previousItemValue = previousItem.get('value')

						if previousItem? and itemValue isnt previousItemValue
							pushToChangeLog {
								parent
								property: "#{Term 'metric'} value"
								action: 'revised'
								item: arrayItem
								value: @_diffStrings(previousItemValue, itemValue)
							}


			# Return only creation change if 0-index, check existence to make sure
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


			currentRevision.entrySeq().forEach ([property, value]) =>
				# Ignore statusReason property, it can't be revised
				return if property is 'statusReason'
				# Account for previousRevision not having this property
				previousRevisionValue = previousRevision.get(property) or ""

				# Plain string & number comparison
				if typeof value in ['string', 'number'] and value isnt previousRevisionValue
					# Unique handling for 'status'
					if property is 'status' and currentRevision.has('statusReason')

						# Special case to convert status 'default' -> 'reactivated'
						if value is 'default' then value = 'reactivated'

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
							value: @_diffStrings(previousRevisionValue, value)
						}

				# Imm List comparison (we assume existence of isList validates Imm.List)
				else if not Imm.is value, previousRevisionValue

					switch @props.type

						when 'planTarget'
							# Generate 'removed' changes
							previousRevisionValue.forEach (item) ->
								unless value.contains(item)
									pushToChangeLog {
										property
										action: 'removed'
										item
									}
							# Generate 'added' changes
							value.forEach (item) ->
								unless previousRevisionValue.contains(item)
									pushToChangeLog {
										property
										action: 'added'
										item
									}

						when 'progNote'
							value.forEach (unit, unitIndex) =>
								switch unit.get('type')

									when 'basic'

										unit.entrySeq().forEach ([property, value]) =>
											previousValue = previousRevisionValue.getIn [unitIndex, property]
											parent = unit.get('name')

											processChanges {parent, property, value, previousValue}

									when 'plan'

										unit.get('sections').forEach (section, sectionIndex) =>
											section.get('targets').forEach (target, targetIndex) =>
												target.entrySeq().forEach ([property, value]) =>
													# Grab the same target value from prev revision
													previousValue = previousRevisionValue.getIn [
														unitIndex
														'sections', sectionIndex
														'targets', targetIndex, property
													]
													parent = target.get('name')

													processChanges {parent, property, value, previousValue}

									else
										throw new Error "Unknown unit type: #{unit.get('type')}"

						else
							throw new Error "Unknown RevisionHistory 'type': #{@props.type}"

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
							type: @props.type
							metricsById: @props.metricsById
							programsById: @props.programsById
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

			userProgramId = revision.get('authorProgramId')
			userProgram = @props.programsById.get(userProgramId) or Imm.Map()

			# Special cases made for planTarget types
			isPlanTarget = @props.type is 'planTarget'
			isTargetStatusChange = isPlanTarget and not (changeLog.first().get('action') in ['revised'])

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

						ColorKeyBubble({
							colorKeyHex: userProgram.get('colorKeyHex')
							popup: {
								title: userProgram.get('name')
								content: userProgram.get('description')
								placement: 'left'
							}
						})
					)
				)

				R.div({className: 'changeLog'},
					(changeLog.map (entry, index) =>
						ChangeLogEntry({
							key: index
							index
							entry
							revision
							isPlanTarget
							type: @props.type
							dataModelName: @props.dataModelName
							metricsById: @props.metricsById
							onToggleSnapshot: @_toggleSnapshot
							isSnapshotVisible: @state.isSnapshotVisible
							disableSnapshot: @props.disableSnapshot
						})
					)
					(if isPlanTarget and not isTargetStatusChange
						RevisionSnapshot({
							revision
							metricsById: @props.metricsById
						})
					)
				)
			)

	ChangeLogEntry = React.createFactory React.createClass
		displayName: 'ChangeLogEntry'
		mixins: [React.addons.PureRenderMixin]

		render: ->
			entry = @props.entry

			isCreationEntry = entry.get('action') is 'created'

			# Account for terminology metricIds -> metrics
			if entry.get('property') is 'metricIds'
				entry = entry.set('property', 'metric')

			R.article({className: 'entry', key: @props.index},
				# # TODO: Restore as Diffing selector
				# (if not @props.disableSnapshot and @props.index is 0 and entry.get('action') isnt 'created'
				# 	R.button({
				# 		className: 'btn btn-default btn-xs snapshotButton'
				# 		onClick: @props.onToggleSnapshot
				# 	},
				# 		if not @props.isSnapshotVisible then "view" else "hide"
				# 		" full revision"
				# 	)
				# )

				R.span({className: 'action'},
					# Different display cases for indication of change
					(if entry.get('action') is 'created'
						"#{capitalize entry.get('action')} #{entry.get('property')}
						#{if @props.isPlanTarget then ' as:' else ''}"
					else if entry.has('reason') # Status change
						"#{capitalize entry.get('value')} #{@props.dataModelName}"
					else if entry.has('parent') and not entry.get('parent').has? # Parent isn't an Imm Map obj
						"#{capitalize entry.get('action')} #{entry.get('property')} for #{entry.get('parent')}"
					else
						"#{capitalize entry.get('action')} #{entry.get('property')}"
					)

					": " if not @props.isPlanTarget and not isCreationEntry
				)

				(if isCreationEntry and not @props.disableSnapshot
					# We can show full snapshot for dataModel creation
					RevisionSnapshot({
						revision: @props.revision
						dataModelName: @props.dataModelName
						metricsById: @props.metricsById
					})

				# Unique handling for metrics
				else if entry.get('property') in [Term('metric'), "#{Term 'metric'} value"]

					if typeof entry.get('item') is 'string'
						# This changeLog entry is a single ID string, so fetch latest metric
						metricId = entry.get('item')
						metric = @props.metricsById.get metricId
					else
						# Assume item is the metric object itself
						metric = entry.get('item')

					MetricWidget({
						value: entry.get('value') # Use diffed value if exists
						isEditable: false
						name: metric.get('name')
						definition: metric.get('definition')
						tooltipViewport: 'article'
						styleClass: 'clear' unless entry.get('value')
					})


				else if entry.get('property') is 'value'
					metric = entry.get('item')

				else if @props.isPlanTarget and entry.get('reason')
					": \"#{entry.get('reason')}\""

				else if not @props.isPlanTarget
					if entry.get('reason') then "\"#{entry.get('reason')}\"" else entry.get('value')
				)

			)

	RevisionSnapshot = ({revision, metricsById}) ->
		hasMetrics = revision.get('metricIds')?

		R.div({className: 'snapshot'},
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