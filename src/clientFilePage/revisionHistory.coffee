# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

Imm = require 'immutable'
Term = require '../term'
{diffChars} = require 'diff'

load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	MetricWidget = require('../metricWidget').load(win)

	{FaIcon, renderLineBreaks, showWhen, 
	stripMetadata, formatTimestamp, capitalize} = require('../utils').load(win)

	RevisionHistory = React.createFactory React.createClass
		displayName: 'RevisionHistory'
		mixins: [React.addons.PureRenderMixin]

		getDefaultProps: -> {
			terms: {}
			metricsById: Imm.List()
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

			currentRevision.entrySeq().forEach ([property, value]) =>
				previousValue = previousRevision.get(property)

				# Plain string & number comparison
				if typeof value in ['string', 'number'] and value isnt previousValue
					entry = {
						property
						action: 'revised'
						value: @_diffStrings(previousValue, value)
					}
					# We'll need the statusReason for 'status' if exists
					if property is 'status' and currentRevision.has('statusReason')
						entry.statusReason = currentRevision.has('statusReason')

					pushToChangeLog(entry)

				# Imm.List comparison
				# For now, let's assume this can only be an Imm List of IDs
				else if not Imm.is value, previousValue
					# Generate 'removed' list items
					previousValue
					.filterNot (metricId) -> value.contains(metricId)
					.forEach (arrayItem) -> pushToChangeLog {
						property
						action: 'removed'
						value: arrayItem
					}
					# Generate 'added' list items
					value
					.filterNot (metricId) -> previousValue.contains(metricId)
					.forEach (arrayItem) -> pushToChangeLog {
						property
						action: 'added'
						value: arrayItem
					}

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
				R.div({className: 'heading'}, "Revision History")

				(if revisions.isEmpty()
					R.div({className: 'noRevisions'},
						"This #{@props.dataModelName} is new.  ",
						"It won't have any history until the #{Term 'client file'} is saved."
					)
				else
					R.div({className: 'revisions'},
						revisions.map (revision) => RevisionChangeLog({
							key: revision.get('revisionId')
							revision
							metricsById: @props.metricsById
							dataModelName: @props.dataModelName
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

			return R.section({className: 'revision'},
				R.div({className: 'header'},
					R.div({className: 'author'},
						FaIcon('user')
						revision.get('author')
					)
					R.div({className: 'timestamp'},
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
						})
					)
					(if @state.isSnapshotVisible
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

			# Account for terminology metricIds -> metrics
			if entry.get('property') is 'metricIds'
				entry = entry.set('property', 'metric')

			R.article({className: 'entry', key: @props.index},
				# Only show snapshotButton on first changeLogEntry
				(if @props.index is 0 and entry.get('action') isnt 'created'
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
						"#{capitalize entry.get('action')} #{entry.get('property')} as: "
					else if entry.get('statusReason')
						"#{capitalize entry.get('value')} #{@props.dataModelName} because: "
					else
						"#{capitalize entry.get('action')} #{entry.get('property')}: "
					)
				)

				(if entry.get('action') is 'created'
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
					__html = entry.get('statusReason') or entry.get('value')

					R.div({
						className: 'value'
						dangerouslySetInnerHTML: {__html}
					})
				)
			)

	RevisionSnapshot = (props) ->
		{revision, metricsById, isAnimated} = props

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

	return RevisionHistory

module.exports = {load}