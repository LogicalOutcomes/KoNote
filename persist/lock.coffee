Async = require 'async'
Fs = require 'fs'
Imm = require 'immutable'
Moment = require 'moment'
Path = require 'path'
Rimraf = require 'rimraf'

{IOError, TimestampFormat} = require './utils'

leaseTime = 3 * 60 * 1000 # ms
leaseRenewalInterval = 1 * 60 * 1000 # ms

class Lock
	constructor: (@_path, @_nextExpiryTimestamp, code) ->
		if code isnt 'privateaccess'
			# See Lock.acquire instead
			throw new Error "Lock constructor should only be used internally"

		@_released = false
		@_renewInterval = setInterval =>
			@_renew (err) =>
				if err
					console.error err
					console.error err.stack
					return
		, leaseRenewalInterval

	@acquire: (dataDir, lockId, cb) ->
		lockDir = Path.join(dataDir, '_locks', lockId)

		Fs.mkdir lockDir, (err) =>
			if err
				# If lock is already taken
				if err.code is 'EEXIST'
					Lock._cleanIfStale dataDir, lockId, cb
					return

				cb new IOError err
				return

			# Got the lock, now we need to write an expiry timestamp
			Lock._writeExpiryTimestamp lockDir, (err, expiryTimestamp) ->
				if err
					cb err
					return

				cb null, new Lock(lockDir, expiryTimestamp, 'privateaccess')

	@_cleanIfStale: (dataDir, lockId, cb) ->
		lockDir = Path.join(dataDir, '_locks', lockId)

		expiryLock = null
		Async.series [
			(cb) ->
				Lock._isStale lockDir, (err, isStale) ->
					if err
						cb err
						return

					if isStale
						# Proceed
						cb()
					else
						cb new LockInUseError()
			(cb) ->
				# The lock has expired, so we need to safely reclaim it while
				# preventing others from doing the same.

				Lock.acquire dataDir, lockId + '.expiry', (err, result) ->
					if err
						cb err
						return

					expiryLock = result
					cb()
			(cb) ->
				Lock._isStale lockDir, (err, isStale) ->
					if err
						cb err
						return

					if isStale
						# Proceed
						cb()
					else
						cb new LockInUseError()
			(cb) ->
				Rimraf lockDir, (err) ->
					if err
						cb new IOError err
						return

					cb()
			(cb) ->
				expiryLock.release cb
		], (err) ->
			if err
				cb err
				return

			Lock.acquire dataDir, lockId, cb

	@_isStale: (lockDir, cb) ->
		Lock._readExpiryTimestamp lockDir, (err, ts) ->
			if err
				cb err
				return

			if ts?
				now = Moment()
				isStale = Moment(ts, TimestampFormat).isBefore now

				cb null, isStale
				return

			# There were no expiry timestamps in the directory.
			# This might be because we read the directory while another
			# instance was acquiring or releasing the lock.
			# Or, it's because the other instance died mid-operation.

			# Wait 5 seconds and try again, just to be sure
			setTimeout ->
				Lock._readExpiryTimestamp lockDir, (err, ts) ->
					if err
						cb err
						return

					if ts?
						# There was a timestamp this time, so it's probably not
						# safe to do anything.
						cb null, false
						return

					# Still nothing.  Probably an error case.
					# Let's proceed as if it's a stale lock.
					cb null, true
			, 5000

	_renew: (cb) ->
		if @_hasLeaseExpired()
			clearInterval @_renewInterval
			@_renewInterval = null
			@_released = true
			cb new Error "cannot renew, lease already expired"
			return

		Lock._writeExpiryTimestamp @_path, (err, expiryTimestamp) =>
			if err
				cb err
				return

			# Actual expiry time is the latest of all expiry times written,
			# so we only need to update the next expiry time if expiryTimestamp
			# is later.
			if Moment(expiryTimestamp, TimestampFormat).isAfter Moment(@_nextExpiryTimestamp, TimestampFormat)
				@_nextExpiryTimestamp = expiryTimestamp

			cb()

	release: (cb=(->)) ->
		# If lease has expired
		if @_hasLeaseExpired() or @_released
			process.nextTick ->
				cb()
			return

		clearInterval @_renewInterval
		@_renewInterval = null
		@_released = true

		Rimraf @_path, (err) ->
			if err
				cb new IOError err
				return

			cb()

	_hasLeaseExpired: ->
		return Moment(@_nextExpiryTimestamp, TimestampFormat).isBefore Moment()

	@_readExpiryTimestamp: (lockDir, cb) ->
		Fs.readdir lockDir, (err, fileNames) ->
			if err
				cb new IOError err
				return

			expiryTimestamps = Imm.List(fileNames)
			.filter (fileName) ->
				return fileName[0...'expire-'.length] is 'expire-'
			.map (fileName) ->
				return Moment(fileName['expire-'.length...], TimestampFormat)
			.sort()

			if expiryTimestamps.size is 0
				cb null, null
				return

			result = expiryTimestamps.last().format(TimestampFormat)

			cb null, result

	@_writeExpiryTimestamp: (lockDir, cb) ->
		expiryTimestamp = Moment().add(leaseTime, 'ms').format(TimestampFormat)
		expiryTimestampFile = Path.join(lockDir, 'expire-' + expiryTimestamp)
		Fs.writeFile expiryTimestampFile, 'expiry-time', (err) ->
			if err
				cb new IOError err
				return

			cb null, expiryTimestamp

class LockInUseError extends Error
	constructor: ->
		super

Lock.LockInUseError = LockInUseError

module.exports = Lock
