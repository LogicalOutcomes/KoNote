Assert = require 'assert'
Async = require 'async'
Fs = require 'fs'
Imm = require 'immutable'
Mkdirp = require 'mkdirp'
Moment = require 'moment'
Path = require 'path'
Rimraf = require 'rimraf'

Lock = require '../../persist/lock'
{TimestampFormat} = require '../../persist/utils'

dataDir = Path.join process.cwd(), 'testData'
locksDir = Path.join dataDir, '_locks'
tmpDir = Path.join dataDir, '_tmp'
session = {
	userName: 'user1'
	dataDirectory: dataDir
	persist: {
		eventBus: {
			on: (a, b) ->
		}
	}
}

describe 'Lock', ->
	beforeEach (cb) ->
		Async.series [
			(cb) ->
				Mkdirp locksDir, cb
			(cb) ->
				Mkdirp tmpDir, cb
		], cb

	afterEach (cb) ->
		Rimraf dataDir, cb

	it 'acquire and release', (cb) ->
		Lock.acquire session, 'lock1', (err, lock1) ->
			if err
				cb err
				return

			Assert lock1
			Assert Fs.existsSync Path.join(locksDir, 'lock1')

			lock1.release (err) ->
				if err
					cb err
					return

				Assert not Fs.existsSync Path.join(locksDir, 'lock1')
				cb()	

	it 'lock twice, then release', (cb) ->
		Lock.acquire session, 'lock1', (err, lock1) ->
			if err
				cb err
				return

			Assert lock1

			Lock.acquire session, 'lock1', (err, result) ->
				Assert err instanceof Lock.LockInUseError
				Assert not result

				lock1.release (err) ->
					if err
						cb err
						return

					Assert not Fs.existsSync Path.join(locksDir, 'lock1')
					cb()

	it 'return LockInUseError metadata/username when locked', (cb) ->
		Lock.acquire session, 'lock1', (err, lock1) ->
			if err
				cb err
				return

			Assert lock1

			Lock.acquire session, 'lock1', (err, result) ->
				Assert err instanceof Lock.LockInUseError
				Assert err.metadata
				Assert err.metadata.userName
				Assert not result

				cb()


	# Takes 10s to run
	it.skip 'replace incomplete lock', (cb) ->
		Fs.mkdirSync Path.join(locksDir, 'lock1')

		Lock.acquire session, 'lock1', (err, lock1) ->
			if err
				cb err
				return

			Assert lock1

			lock1.release (err) ->
				if err
					cb err
					return

				Assert not Fs.existsSync Path.join(locksDir, 'lock1')
				cb()

	it 'replace stale lock', (cb) ->
		# TODO make this have an expired timestamp
		Fs.mkdirSync Path.join(locksDir, 'lock1')
		ts = Moment().subtract(10, 'seconds').format(TimestampFormat)
		Fs.writeFileSync Path.join(locksDir, 'lock1', "expire-#{ts}"), 'test'

		Lock.acquire session, 'lock1', (err, lock1) ->
			if err
				cb err
				return

			Assert lock1

			lock1.release (err) ->
				if err
					cb err
					return

				Assert not Fs.existsSync Path.join(locksDir, 'lock1')
				cb()

	it 'acquire lock when free (make available after 800ms)', (cb) ->
		Lock.acquire session, 'lock1', (err, lock1) ->
			if err
				cb err
				return

			Assert lock1

			# Release original lock after 1s
			setTimeout(->
				lock1.release (err) ->
					if err
						cb err
						return
						
			, 500)

			# Aggressively check for lock
			Lock.acquireWhenFree(session, 'lock1', (err, newLock) ->
				if err
					cb err
					return

				Assert newLock
				cb()

			, 100)




