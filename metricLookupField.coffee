# An auto-completing text field for selecting a metric.

load = (win) ->
	$ = win.jQuery
	React = win.React
	R = React.DOM

	{
		FaIcon
		renderLineBreaks
		showWhen
		truncateText
	} = require('./utils').load(win)

	MetricLookupField = React.createFactory React.createClass
		componentDidMount: ->
			lookupField = $(@refs.lookupField.getDOMNode())

			lookupField.typeahead {
				highlight: true
				hint: false
				minLength: 1
			}, {
				name: 'metrics'
				source: @_lookupMetric
				displayKey: 'name'
				templates: {
					empty: '''
						<div class="empty">
							No metrics found under that name.  You can create a new metric using TODO
						</div>
					'''
					suggestion: (metric) =>
						suggestionComponent = Suggestion({metric})
						return React.renderToString(suggestionComponent)
				}
			}

			lookupField.on 'typeahead:selected', (event, metric) =>
				lookupField.typeahead 'val', ''
				@props.onSelection metric.id
		render: ->
			return R.div({className: 'metricLookupField'},
				R.input({
					className: 'lookupField form-control typeahead'
					ref: 'lookupField'
					placeholder: @props.placeholder
				})
			)
		_lookupMetric: (query, cb) ->
			query = query.toLowerCase()

			cb(
				@props.metrics
				.filter (metric) =>
					name = metric.get('name')
					definition = metric.get('definition')
					return name.toLowerCase().includes(query) or definition.toLowerCase().includes(query)
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
