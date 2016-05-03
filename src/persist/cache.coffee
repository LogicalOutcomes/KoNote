# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# This module provides a simple key-value store suitable as a cache.
# Keys must be strings. Values can be anything except undefined or null.

Moment = require 'moment'

class Cache
	# timeToLive: number of milliseconds until an entry expires
	constructor: (@timeToLive) ->
		@_data = {}

	# Accesses the cache entry with the specified key.
	#
	# key: must be a string
	# returns: null or the cache entry value
	get: (key) ->
		entry = @_data[key]

		unless entry?
			return null

		now = Moment()

		# If entry is expired
		if entry.expiresAt.isBefore(now)
			delete @_data[key]
			return null

		return entry.value

	# Add/replace an entry.  If an entry already exists under this key, it is
	# replaced and the expiry time is reset.
	#
	# key: must be a string
	# value: anything except null or undefined
	set: (key, value) ->
		unless value?
			throw new Error "cannot add value to cache: #{value}"

		@_data[key] = {
			expiresAt: Moment().add(@timeToLive, 'ms')
			value
		}
		return

	# Update an entry without affecting the expiry time.
	# updateFn is provided with the current value of the entry under this key,
	# and should return a new value.  If no entry exists under this key,
	# updateFn is not called and no changes are made.
	#
	# key: must be a string
	# updateFn(oldValue) -> newValue: a function that converts the old value to a new value
	# returns: true if entry was updated, false if no entry was found for key
	update: (key, updateFn) ->
		oldValue = @get(key)

		if oldValue?
			newValue = updateFn(oldValue)
			@_data[key].value = newValue
			return true

		return false

	# Remove the entry with the specified key (if one exists).
	#
	# key: must be a string
	remove: (key) ->
		delete @_data[key]
		return

module.exports = Cache
