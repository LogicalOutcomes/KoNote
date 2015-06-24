# A generic dialog component

load = (win) ->
	$ = win.jQuery
	React = win.React
	R = React.DOM
	{FaIcon} = require('./utils').load(win)

	Dialog = React.createFactory React.createClass
		render: ->
			return R.div({
				className: [
					'dialogContainer'
					@props.containerClasses.join(' ')
				].join(' ')
				onClick: @_onBackgroundClick
			},
				R.div({className: 'dialog panel panel-primary'},
					R.div({className: 'panel-heading'},
						R.h3({className: 'panel-title'}, @props.title)
						R.span({
							className: 'panel-quit'
							onClick: @props.onClose
						}, FaIcon('times'))
					)
					R.div({className: 'panel-body'},
						@props.children
					)
				)
			)
		_onBackgroundClick: (event) ->
			# If click was on background, not the dialog itself
			if event.target.classList.contains 'dialogContainer'
				@props.onClose()

	return Dialog

module.exports = {load}
