# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

load = (win, classNames...) ->
	React = win.React
	ReactBootstrap = win.ReactBootstrap

	_ = require 'underscore'

	factories = {}

	_.forEach classNames, (className) ->
		unless ReactBootstrap[className]?
			throw new Error "ReactBootstrap class '#{className}' is undefined"

		factories[className] = React.createFactory ReactBootstrap[className]

	return factories

module.exports = {load}
