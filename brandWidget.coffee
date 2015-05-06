# Displays the branding logo etc in a specified corner of the

load = (win) ->
	$ = win.jQuery
	React = win.React
	R = React.DOM
	{FaIcon, renderLineBreaks, showWhen} = require('./utils').load(win)

	BrandWidget = React.createFactory React.createClass
		render: ->
			return R.div({
				className: [
					'brandContainer',
					'reverse' if @props.reverse
				].join(' ')
				},
				R.img({
					src: './img/konode-kn.svg',
					className: 'logoKN'
				})
				R.img({
					src: './img/konode-konode.svg',
					className: 'logoKonode'
				})
			)

	return BrandWidget

module.exports = {load}