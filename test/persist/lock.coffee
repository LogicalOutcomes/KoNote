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

describe 'Lock', ->
	beforeEach (cb) ->
		Mkdirp locksDir, cb

	afterEach (cb) ->
		Rimraf dataDir, cb

	it 'acquire and release', (cb) ->
		Lock.acquire dataDir, 'lock1', (err, lock1) ->
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
		Lock.acquire dataDir, 'lock1', (err, lock1) ->
			if err
				cb err
				return

			Assert lock1

			Lock.acquire dataDir, 'lock1', (err, result) ->
				Assert err instanceof Lock.LockInUseError
				Assert not result

				lock1.release (err) ->
					if err
						cb err
						return

					Assert not Fs.existsSync Path.join(locksDir, 'lock1')
					cb()

	# Takes 10s to run
	it.skip 'replace incomplete lock', (cb) ->
		Fs.mkdirSync Path.join(locksDir, 'lock1')

		Lock.acquire dataDir, 'lock1', (err, lock1) ->
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

		Lock.acquire dataDir, 'lock1', (err, lock1) ->
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
