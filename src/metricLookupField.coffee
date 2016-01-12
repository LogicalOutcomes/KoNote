# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# An auto-completing text field for selecting a metric.
#
# I used typeahead.js for this field.  This was a poor life choice.
# The library provides very little functionality, and made some things more
# difficult.  We should probably just implement our own auto-complete
# functionality -- it might even make this file shorter.

load = (win) ->
	$ = win.jQuery
	React = win.React
	R = React.DOM
	Bootbox = win.bootbox
	ReactDOMServer = win.ReactDOMServer

	LayeredComponentMixin = require('./layeredComponentMixin').load(win)
	DefineMetricDialog = require('./defineMetricDialog').load(win)
	Config = require('./config')
	Term = require('./term')

	{
		FaIcon
		renderLineBreaks
		showWhen
		truncateText
	} = require('./utils').load(win)

	MetricLookupField = React.createFactory React.createClass
		mixins: [LayeredComponentMixin]
		getInitialState: ->
			return {
				isDefineMetricDialogVisible: false
			}
		componentDidMount: ->
			lookupField = $(@refs.lookupField)

			lookupField.typeahead {
				highlight: true
				hint: false
				minLength: 1
			}, {
				name: 'metrics'
				source: @_lookupMetric
				displayKey: 'name'
				templates: {
					empty: """
						<div class="empty">
							No #{Term 'metric'} found under that name.
						</div>
					"""
					suggestion: (metric) =>
						suggestionComponent = Suggestion({metric})
						return ReactDOMServer.renderToString(suggestionComponent)
					footer: (query, isEmpty) ->
						return """
							<div class="createMetricContainer">
								<button class="createMetric btn btn-success">Define a new #{Term 'metric'}</button>
							</div>
						"""
				}
			}

			lookupField.on 'typeahead:selected', (event, metric) =>
				lookupField.typeahead 'val', ''				
				@props.onSelection metric.id

			# We need to reattach an event listener to the create button, but
			# it would get wiped out every time typeahead.js rerenders.  So,
			# instead, we'll let the event bubble up to an ancestor element and
			# check the target.
			lookupField.parent().on 'click', (event) =>
				target = event.target
				if target.classList.contains('btn') and target.classList.contains('createMetric')
					#check if metric exists before creating
					match = @props.metrics.toJS().filter (match) -> match.name == lookupField.typeahead 'val'
					if match[0]
						Bootbox.alert "<strong>#{Term 'Metric'} already exists!</strong>
						<br><br>Please select an existing #{Term 'metric'} from the search field
						or use a unique name to create a new #{Term 'metric'}.", ->
							# TODO
							# how can we refocus the lookup field?
							lookupField.typeahead 'val', ''
							lookupField.focus()
							return
					else
						lookupField.typeahead 'close'
						@_createMetric()
		render: ->
			return R.div({className: 'metricLookupField'},
				R.input({
					className: 'lookupField form-control typeahead'
					ref: 'lookupField'
					placeholder: @props.placeholder
				})
			)

		renderLayer: ->
			unless @state.isDefineMetricDialogVisible
				return R.div()

			return DefineMetricDialog({
				metricQuery: $(@refs.lookupField).val()
				onCancel: =>
					@setState {isDefineMetricDialogVisible: false}
				onSuccess: (newMetric) =>
					@setState {isDefineMetricDialogVisible: false}

					lookupField = $(@refs.lookupField)
					lookupField.typeahead 'val', ''
					lookupField.focus()

					@props.onSelection newMetric.get('id')
			})
		_createMetric: ->
			@setState {isDefineMetricDialogVisible: true}
		_lookupMetric: (query, cb) ->
			query = query.toLowerCase()

			cb(
				@props.metrics
				.filter (metric) =>
					name = metric.get('name')
					definition = metric.get('definition')

					# Looks for an exact match in either the name or
					# definition.  It might be useful to change this to a
					# word-by-word fuzzy comparison.
					return name.toLowerCase().includes(query) or definition.toLowerCase().includes(query)
				.take(10) # limit to first 10 results
				.toJS()
			)

	Suggestion = React.createFactory React.createClass
		render: ->
			return R.div({},
				R.span({className: 'name'},
					@props.metric.name
				)
				' — ' # &mdash;
				R.span({className: 'definition'},
					renderLineBreaks(truncateText(75, @props.metric.definition))
				)
			)

	return MetricLookupField

module.exports = {load}
