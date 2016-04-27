# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Post-processes terms identified Config.terminology
# Require into pages as Terms = require('./terms')

# Refrain from using this module in internal error/crashHandler messages

Config = require './config'
Pluralize = require 'pluralize'
_ = require 'underscore'

# Utility functions

capitalize = (word) ->
  word.replace /(?:^|\s)\S/g, (a) ->
    a.toUpperCase()

pluralizeLastWord = (string) ->
	# Split string into words, pluralize last word, join back together
	stringWords = string.split " "
	lastWordIndex = stringWords.length - 1
	stringWords[lastWordIndex] = Pluralize stringWords[lastWordIndex]
	return stringWords.join " "


# Generate variations of capitalized and pluralized terms

generatedTerms = {}

_.each Config.terminology, (value, key) ->	
	capKey = capitalize key.toString()
	capValue = capitalize value	

	generatedTerms[key] = value
	generatedTerms[capKey] = capValue
	generatedTerms[pluralizeLastWord(key)] = pluralizeLastWord(value)
	generatedTerms[pluralizeLastWord(capKey)] = pluralizeLastWord(capValue)

module.exports = (term) ->
	# TODO: Logic to switch out "a", "an", etc
	if generatedTerms[term]
		return generatedTerms[term]
	else
		throw new Error "'#{term}'' does not exist in Terms(), or is not a valid 
		plural of the root word."