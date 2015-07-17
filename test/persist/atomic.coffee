Assert = require 'assert'
Async = require 'async'
Fs = require 'fs'
Mkdirp = require 'mkdirp'
Path = require 'path'
Rimraf = require 'rimraf'

Atomic = require '../../persist/atomic'

dataDir = 'atomicTestData'
tmpDir = 'atomicTestTmp'

describe 'Atomic', ->
	before (cb) ->
		Async.series [
			(cb) ->
				Rimraf dataDir, cb
			(cb) ->
				Rimraf tmpDir, cb
		], cb

	beforeEach (cb) ->
		Async.series [
			(cb) ->
				Mkdirp dataDir, cb
			(cb) ->
				Mkdirp tmpDir, cb
		], cb

	afterEach (cb) ->
		Async.series [
			(cb) ->
				Rimraf dataDir, cb
			(cb) ->
				Rimraf tmpDir, cb
		], cb

	describe 'writeFile', ->
		it 'should work and leave tmp empty', (cb) ->
			fd = null
			op = null

			Async.series [
				(cb) ->
					path = Path.join(dataDir, 'a')
					Atomic.writeFile path, tmpDir, (err, fileDescriptor, atomicOperation) ->
						if err
							cb err
							return

						fd = fileDescriptor
						op = atomicOperation
						cb()
				(cb) ->
					Fs.write fd, 'abc', cb
				(cb) ->
					Assert not op.isCommitted

					op.commit cb
				(cb) ->
					Assert op.isCommitted

					Fs.readdir dataDir, (err, files) ->
						if err
							cb err
							return

						Assert.deepEqual files, ['a']
						cb()
				(cb) ->
					Fs.readFile Path.join(dataDir, 'a'), 'utf8', (err, data) ->
						if err
							cb err
							return

						Assert.equal data, 'abc'
						cb()
				(cb) ->
					Fs.readdir tmpDir, (err, files) ->
						if err
							cb err
							return

						Assert.deepEqual files, []
						cb()
			], cb

		it 'should overwrite other files', (cb) ->
			path = Path.join(dataDir, 'a')

			fd = null
			op = null

			Async.series [
				(cb) ->
					Fs.writeFile path, 'hey', cb
				(cb) ->
					Atomic.writeFile path, tmpDir, (err, fileDescriptor, atomicOperation) ->
						if err
							cb err
							return

						fd = fileDescriptor
						op = atomicOperation
						cb()
				(cb) ->
					Fs.write fd, 'abc', cb
				(cb) ->
					op.commit cb
				(cb) ->
					Fs.readFile path, 'utf8', (err, data) ->
						Assert not err

						Assert.equal data, 'abc'
						cb()
			], cb

	describe 'writeDirectory', ->
		it 'should work and leave tmp empty', (cb) ->
			dest = Path.join(dataDir, 'd')
			tmpDest = null
			op = null

			Async.series [
				(cb) ->
					Atomic.writeDirectory dest, tmpDir, (err, tempPath, atomicOperation) ->
						if err
							cb err
							return

						tmpDest = tempPath
						op = atomicOperation
						cb()
				(cb) ->
					Fs.writeFile Path.join(tmpDest, 'm'), 'stuff', cb
				(cb) ->
					Fs.writeFile Path.join(tmpDest, 'n'), 'stuff', cb
				(cb) ->
					Assert not op.isCommitted

					op.commit cb
				(cb) ->
					Assert op.isCommitted

					Fs.readdir dataDir, (err, files) ->
						if err
							cb err
							return

						Assert.deepEqual files, ['d']
						cb()
				(cb) ->
					Fs.readdir dest, (err, files) ->
						if err
							cb err
							return

						Assert.deepEqual files, ['m', 'n']
						cb()
				(cb) ->
					Fs.readdir tmpDir, (err, files) ->
						if err
							cb err
							return

						Assert.deepEqual files, []
						cb()
			], cb

		it 'should overwrite empty dirs', (cb) ->
			dest = Path.join(dataDir, 'd')
			tmpDest = null
			op = null

			Async.series [
				(cb) ->
					Fs.mkdir dest, cb
				(cb) ->
					Atomic.writeDirectory dest, tmpDir, (err, tempPath, atomicOperation) ->
						if err
							cb err
							return

						tmpDest = tempPath
						op = atomicOperation
						cb()
				(cb) ->
					Fs.writeFile Path.join(tmpDest, 'm'), 'stuff', cb
				(cb) ->
					Fs.writeFile Path.join(tmpDest, 'n'), 'stuff', cb
				(cb) ->
					op.commit cb
				(cb) ->
					Fs.readdir dest, (err, files) ->
						if err
							cb err
							return

						Assert.deepEqual files, ['m', 'n']
						cb()
			], cb

		it 'should fail to overwrite dirs containing a file', (cb) ->
			dest = Path.join(dataDir, 'd')
			tmpDest = null
			op = null

			Async.series [
				(cb) ->
					Fs.mkdir dest, cb
				(cb) ->
					Fs.writeFile Path.join(dest, 'x'), 'abc', cb
				(cb) ->
					Atomic.writeDirectory dest, tmpDir, (err, tempPath, atomicOperation) ->
						if err
							cb err
							return

						tmpDest = tempPath
						op = atomicOperation
						cb()
				(cb) ->
					Fs.writeFile Path.join(tmpDest, 'm'), 'stuff', cb
				(cb) ->
					Fs.writeFile Path.join(tmpDest, 'n'), 'stuff', cb
				(cb) ->
					op.commit (err) ->
						Assert err
						Assert.equal err.code, 'ENOTEMPTY'
						cb()
			], cb

	describe 'deleteDirectory', ->
		it 'should work and leave tmp empty', (cb) ->
			target = Path.join dataDir, 'dir1'

			Async.series [
				(cb) ->
					Fs.mkdir target, cb
				(cb) ->
					Fs.writeFile Path.join(target, 'x'), 'abc', cb
				(cb) ->
					Atomic.deleteDirectory target, tmpDir, cb
				(cb) ->
					Fs.readdir dataDir, (err, files) ->
						if err
							cb err
							return

						Assert.deepEqual files, []
						cb()
				(cb) ->
					Fs.readdir tmpDir, (err, files) ->
						if err
							cb err
							return

						Assert.deepEqual files, []
						cb()
			], cb
