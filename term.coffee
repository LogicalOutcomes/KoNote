# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Post-processes terms identified Config.terminology
# Require into pages as Terms = require('./terms')

# Refrain from using this module in internal error/crashHandler messages

Config = require './config'
Pluralize = require 'pluralize'
_ = require 'underscore'

capitalize = (word) ->
  word.replace /(?:^|\s)\S/g, (a) ->
    a.toUpperCase()

generatedTerms = {}

_.each Config.terminology, (value, name) ->	
	capName = capitalize name.toString()
	capValue = capitalize value

	# TODO: Combo of 1 capitalized word and 1 lowercase word ("Progress note")
	generatedTerms[name] = value
	generatedTerms[capName] = capValue
	generatedTerms[Pluralize(name)] = Pluralize(value)
	generatedTerms[Pluralize(capName)] = Pluralize(capValue)	

# console.log "configTerms", generatedTerms

module.exports = (term) ->
	# TODO: Logic to switch out "a", "an", etc	
	if generatedTerms[term]
		return generatedTerms[term]
	else
		throw new Error "'#{term}'' does not exist in Terms(), or is not a valid 
		plural of the root word."