# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# This module's API is documented on the wiki.

Async = require 'async'
Fs = require 'fs'
Imm = require 'immutable'
Moment = require 'moment'
Path = require 'path'

Atomic = require './atomic'

{CustomError, IOError, TimestampFormat} = require './utils'

leaseTime = 3 * 60 * 1000 # ms
leaseRenewalInterval = 1 * 60 * 1000 # ms

class Lock
	constructor: (@_path, @_tmpDirPath, @_nextExpiryTimestamp, code) ->
		if code isnt 'privateaccess'
			# See Lock.acquire instead
			throw new Error "Lock constructor should only be used internally"

		@_released = false
		@_isCheckingForLock = false

		@_renewInterval = setInterval =>
			@_renew (err) =>
				if err
					console.error err
					console.error err.stack
					return
		, leaseRenewalInterval

	@acquire: (session, lockId, cb) ->
		dataDir = session.dataDirectory

		tmpDirPath = Path.join(dataDir, '_tmp')
		lockDirDest = Path.join(dataDir, '_locks', lockId)

		lockDir = null
		lockDirOp = null
		expiryTimestamp = null

		Async.series [
			(cb) ->
				Atomic.writeDirectory lockDirDest, tmpDirPath, (err, tmpLockDir, op) ->
					if err
						cb err
						return

					lockDir = tmpLockDir
					lockDirOp = op
					cb()
			(cb) ->
				Lock._writeMetadata session, lockDir, tmpDirPath, (err) ->
					if err
						cb err
						return
					cb()
			(cb) ->
				Lock._writeExpiryTimestamp lockDir, tmpDirPath, (err, ts) ->
					if err
						cb err
						return

					expiryTimestamp = ts
					cb()
			(cb) ->
				lockDirOp.commit (err) ->
					if err
						# If lock is already taken
						if err instanceof IOError and err.cause.code in ['EPERM', 'ENOTEMPTY']
							Lock._cleanIfStale session, lockId, cb
							return

						cb err
						return

					cb()
		], (err) ->
			if err
				cb err
				return

			cb null, new Lock(lockDirDest, tmpDirPath, expiryTimestamp, 'privateaccess')

	@acquireWhenFree: (session, lockId, intervalMins, cb) ->	
		# Makes intervalMinutes optional, keeping cb last
		unless cb
			cb = intervalMins
			intervalMins = 0.5
		else
			# Convert mins to ms
			intervalMs = intervalMins * 60000

		newLock = null
		isCancelled = null

		# Aggressively check lock existance every specified interval(ms)
		Async.until(->			
			return isCancelled or newLock
		(callback) =>
			@acquire session, lockId, (err, lock) ->
				if err
					console.warn "Failed to obtain lock. Retrying in #{60 * intervalMins}s"

				if lock
					console.info "Lock acquired!"
					newLock = lock
					callback()
				else
					# Wait for interval before trying again
					setTimeout callback, intervalMs
		(err) ->
			if isCancelled
				# End loop when operation cancelled
				cb null
			else
				# Found a new lock, delivered through cb
				cb null, newLock
		)

		return {
			# Provides public operation.cancel(cb) method
			cancel: (cb=(->)) -> 
				isCancelled = true
				console.log "Ended lock operation!"
				cb()
		}

	@_cleanIfStale: (session, lockId, cb) ->
		dataDir = session.dataDirectory

		tmpDirPath = Path.join(dataDir, '_tmp')
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
						# Lock is in use, deliver error with metadata
						Lock._readMetadata(lockDir, cb)
						return
			(cb) ->
				# The lock has expired, so we need to safely reclaim it while
				# preventing others from doing the same.

				Lock.acquire session, lockId + '.expiry', (err, result) ->
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
						# Lock is in use, deliver error with metadata
						Lock._readMetadata(lockDir, cb)
						return
			(cb) ->
				Atomic.deleteDirectory lockDir, tmpDirPath, cb
			(cb) ->
				expiryLock.release cb
		], (err) ->
			if err
				# This error comes from @_isStale and @_readMetadata
				if err instanceof LockDeletedError
					# Release expiry lock if exists, then acquire lock again
					if expiryLock?
						expiryLock.release (err) -> 
							if err
								cb err
								return

							Lock.acquire(session, lockId, cb)
					# Just acquire lock again
					else
						Lock.acquire(session, lockId, cb)
					return

				cb err
				return

			Lock.acquire session, lockId, cb

	@_isStale: (lockDir, cb) ->
		Lock._readExpiryTimestamp lockDir, (err, ts) ->
			if err
				cb err
				return

			now = Moment()
			isStale = Moment(ts, TimestampFormat).isBefore now

			cb null, isStale
			return

	_renew: (cb) ->
		if @_hasLeaseExpired()
			clearInterval @_renewInterval
			@_renewInterval = null
			@_released = true
			cb new Error "cannot renew, lease already expired"
			return

		Lock._writeExpiryTimestamp @_path, @_tmpDirPath, (err, expiryTimestamp) =>
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

		Atomic.deleteDirectory @_path, @_tmpDirPath, cb

	_hasLeaseExpired: ->
		return Moment(@_nextExpiryTimestamp, TimestampFormat).isBefore Moment()

	@_readExpiryTimestamp: (lockDir, cb) ->
		Fs.readdir lockDir, (err, fileNames) ->
			if err
				# LockDir has been deleted during operation
				if err.code in ['ENOENT']
					cb new LockDeletedError()
					return

				cb new IOError err
				return

			expiryTimestamps = Imm.List(fileNames)
			.filter (fileName) ->
				# Does this filename start with 'expire-'?
				return fileName[0...'expire-'.length] is 'expire-'
			.map (fileName) ->
				# Parse timestamp as a Moment
				return Moment(fileName['expire-'.length...], TimestampFormat)
			.sort()

			if expiryTimestamps.size is 0
				# OK, there weren't any expiry timestamps in the directory.
				# That should be impossible, and also kinda sucks.
				console.error "Detected lock dir with no expiry timestamp: #{JSON.stringify lockDir}"
				console.error "This shouldn't ever happen."

				# But we don't want to lock the user out of this object forever.
				# So we'll just delete the lock and continue on.
				console.error "Continuing on assumption that lock is stale."

				cb null, Moment(0).format(TimestampFormat)
				return

			result = expiryTimestamps.last().format(TimestampFormat)

			cb null, result

	@_readMetadata: (lockDir, cb) ->
		Fs.readFile Path.join(lockDir, "metadata"), (err, data) ->
			if err
				if err.code in ['ENOENT']
					cb new LockDeletedError()
					return

				cb new IOError err
				return

			cb new LockInUseError JSON.parse(data)

	@_writeExpiryTimestamp: (lockDir, tmpDirPath, cb) ->
		expiryTimestamp = Moment().add(leaseTime, 'ms').format(TimestampFormat)
		expiryTimestampFile = Path.join(lockDir, 'expire-' + expiryTimestamp)

		fileData = new Buffer('expiry-time', 'utf8') # some filler data

		Atomic.writeBufferToFile expiryTimestampFile, tmpDirPath, fileData, (err) ->
			if err
				cb err
				return

			cb null, expiryTimestamp

	@_writeMetadata: (session, lockDir, tmpDirPath, cb) ->
		metadataFile = Path.join(lockDir, 'metadata')

		metadata = new Buffer(JSON.stringify({
			userName: session.userName
		}), 'utf8')

		Atomic.writeBufferToFile metadataFile, tmpDirPath, metadata, cb

class LockDeletedError extends CustomError

class LockInUseError extends CustomError
	constructor: (metadata) ->
		super "Lock is in use by another user"
		@metadata = metadata

Lock.LockInUseError = LockInUseError

module.exports = Lock
