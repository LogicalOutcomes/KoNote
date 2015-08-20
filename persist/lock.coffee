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
						cb new IOError err
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
						if err.code in ['EPERM', 'ENOTEMPTY']
							Lock._cleanIfStale session, lockId, cb
							return

						cb new IOError err
						return

					cb()
		], (err) ->
			if err
				cb err
				return

			cb null, new Lock(lockDirDest, tmpDirPath, expiryTimestamp, 'privateaccess')

	@acquireWhenFree: (session, lockId, cb, interval = 1000) ->		
		newLock = null
		isCancelled = null

		# Aggressively check lock existance every specified interval(ms)
		Async.until(->			
			return isCancelled or newLock
		(callback) =>
			@acquire session, lockId, (err, lock) ->
				if lock
					newLock = lock
					callback()
				else
					setTimeout callback, interval
		(err) ->
			if isCancelled
				cb null
			else
				cb null, newLock
		)

		return {cancel: => isCancelled = true}

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
				Atomic.deleteDirectory lockDir, tmpDirPath, (err) ->
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

			Lock.acquire session, lockId, cb

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

			# OK, there weren't any expiry timestamps in the directory.
			# That should be impossible, and also kinda sucks.
			console.error "Detected lock dir with no expiry timestamp: #{JSON.stringify lockDir}"
			console.error "This shouldn't ever happen."

			# But we don't want to lock the user out of this object forever.
			# So we'll just delete the lock and continue on.
			console.error "Continuing on assumption that lock is stale."

			# isStale = true
			cb null, true

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

		Atomic.deleteDirectory @_path, @_tmpDirPath, (err) ->
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

	@_readMetadata: (lockDir, cb) ->
		Fs.readFile lockDir+"/metadata", (err, data) ->
			if err
				return new IOError err

			cb new LockInUseError null, JSON.parse(data)

	@_writeExpiryTimestamp: (lockDir, tmpDirPath, cb) ->
		expiryTimestamp = Moment().add(leaseTime, 'ms').format(TimestampFormat)
		expiryTimestampFile = Path.join(lockDir, 'expire-' + expiryTimestamp)

		fileData = new Buffer('expiry-time', 'utf8') # some filler data

		Atomic.writeBufferToFile expiryTimestampFile, tmpDirPath, fileData, (err) ->
			if err
				cb new IOError err
				return

			cb null, expiryTimestamp

	@_writeMetadata: (session, lockDir, tmpDirPath, cb) ->
		metadataFile = Path.join(lockDir, 'metadata')

		metadata = new Buffer(JSON.stringify({
			userName: session.userName
		}), 'utf8')

		Atomic.writeBufferToFile metadataFile, tmpDirPath, metadata, (err) ->
			if err
				cb new IOError err
				return

			cb()

class LockInUseError extends CustomError
	constructor: (message, metadata) ->
		super "Lock is in use by another user"
		@metadata = metadata

Lock.LockInUseError = LockInUseError

module.exports = Lock
