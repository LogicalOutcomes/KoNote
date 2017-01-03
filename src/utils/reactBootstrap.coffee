# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Convenience method for turning
# TODO: Come up with better solution for requiring ReactBoostrap components as factories

load = (win, classNames...) ->
	React = win.React
	ReactBootstrap = win.ReactBootstrap

	factories = {}

	classNames.forEach (className) ->
		unless ReactBootstrap[className]?
			throw new Error "ReactBootstrap class '#{className}' is undefined"

		factories[className] = React.createFactory ReactBootstrap[className]

	return factories


module.exports = {load}
