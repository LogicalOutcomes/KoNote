# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# a React widget to drop in wherever events should be displayed
Moment = require 'moment'

load = (win) ->
	$ = win.jQuery
	React = win.React
	R = React.DOM
	
	progEventWidget = React.createFactory React.createClass
		render: ->
			return R.div({className: 'events'}
				R.div({
					className: 'header'
				},
					[(Moment(@props.start, "YYYYMMDDTHHmmssSSSZZ").format 'MMMM D, YYYY [at] HH:mm', "-", @props.end), ": ", @props.title]
				)
			)

	return progEventWidget

module.exports = {load}
