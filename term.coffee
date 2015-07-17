# Post-processes terms identified Config.terminology
# Require into pages as Terms = require('./terms')

# Refrain from using this module in internal error/crashHandler messages

Config = require './config'
Pluralize = require 'pluralize'
_ = require 'underscore'

# String polyfill for capitalization of all words
String::capitalize = ->
  @replace /(?:^|\s)\S/g, (a) ->
    a.toUpperCase()

generatedTerms = {}

_.each Config.terminology, (value, name) ->	
	capName = name.toString().capitalize()
	capValue = value.capitalize()

	# TODO: Combination of 1 capitalized word and 1 lowercase word ("Progress note")
	generatedTerms[name] = value
	generatedTerms[capName] = capValue
	generatedTerms[Pluralize(name)] = Pluralize(value)
	generatedTerms[Pluralize(capName)] = Pluralize(capValue)	

# console.log "configTerms", generatedTerms

fetchTerm = (term) ->
	# TODO: Logic to switch out "a", "an", etc	
	if generatedTerms[term]
		return generatedTerms[term]
	else
		throw new Error "'#{term}'' does not exist in Terms(), or is not a valid 
		plural of the root word."


module.exports = fetchTerm