# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Displays the branding logo etc in a specified corner of the

load = (win) ->
	$ = win.jQuery
	React = win.React
	R = React.DOM
	{FaIcon, renderLineBreaks, showWhen} = require('./utils').load(win)

	BrandWidget = React.createFactory React.createClass
		displayName: 'BrandWidget'
		mixins: [React.addons.PureRenderMixin]
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