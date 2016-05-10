# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Provides file operations implemented atomically.
#
# Normally, file operations involve many steps, and could fail part-way
# through.  The functions in this module are designed to act as if the entire
# operation is only one step -- i.e. it either succeeds 100% or leaves no trace
# that the operation was attempted.  This helps prevent application crashes and
# network problems from corrupting user data.
#
# Most operations require a `tmpDirPath`.  This directory is used as a
# temporary workspace during the operation.

Assert = require 'assert'
Async = require 'async'
Fs = require 'fs'
Path = require 'path'
Rimraf = require 'rimraf'

{generateId, IOError, isValidJSON} = require './utils'

# Atomically write a file to the specified path.
#
# The callback will receive (err, fd, op):
#  - err: possible error object
#  - fd: a file descriptor to be used with Fs.write
#  - op: an AtomicOperation object
#
# Use `fd` to write the file contents.
# Call `op.commit` with a callback to perform the operation.
#
# Note: any existing file at `path` will be overwritten.
writeFile = (path, tmpDirPath, cb) =>
	tmpPath = Path.join tmpDirPath, generateId()

	Fs.open tmpPath, 'w', (err, fd) =>
		if err
			cb new IOError err
			return

		commit = (cb) =>
			Async.series [
				(cb) =>
					Fs.close fd, (err) =>
						if err
							cb new IOError err
							return

						cb()
				(cb) =>
					Fs.rename tmpPath, path, (err) =>
						if err
							# Retry once after 500ms
							setTimeout(=>
								console.log "Retrying..."
								Fs.rename tmpPath, path, (err) =>
									if err
										cb new IOError err
										return
							, 500)

							return

						cb()
			], cb

		cb null, fd, new AtomicOperation(commit)

# Atomically write a buffer to a file at the specified path.
#
# This is a convenience method that wraps around `writeFile`.
# It simplifies cases where the entire file contents are known in advance.
writeBufferToFile = (path, tmpDirPath, dataBuf, cb) =>
	Assert Buffer.isBuffer dataBuf, "dataBuf must be a Buffer"

	fileHandle = null
	fileOp = null

	Async.series [
		(cb) =>
			writeFile path, tmpDirPath, (err, fd, op) =>
				if err
					cb err
					return

				fileHandle = fd
				fileOp = op
				cb()
		(cb) =>
			Fs.write fileHandle, dataBuf, 0, dataBuf.length, (err) =>
				if err
					cb new IOError err
					return

				cb()
		(cb) =>
			fileOp.commit cb
	], cb

# Atomically write stringified JSON to a file at the specified path.
# 
# This is another convienience method that wraps around `writeFile`.
writeJSONToFile = (path, tmpDirPath, dataJSON, cb) =>	
	Assert isValidJSON dataJSON, "dataJSON must be valid JSON"

	fileHandle = null
	fileOp = null

	Async.series [
		(cb) =>
			writeFile path, tmpDirPath, (err, fd, op) =>
				if err
					cb err
					return

				fileHandle = fd
				fileOp = op
				cb()
		(cb) =>
			Fs.write fileHandle, dataJSON, (err) =>
				if err
					cb new IOError err
					return

				cb()
		(cb) =>
			fileOp.commit cb
	], cb

# Atomically create a directory tree at the specified path.
#
# The callback will receive (err, dirPath, op):
#  - err: possible error object
#  - dirPath: a path to a temporary directory for setting up a file tree
#  - op: an AtomicOperation object
#
# Create files and directories inside the directory at `dirPath`, as needed.
# Calling `op.commit` will atomically move the file tree at `dirPath` to
# `path`.
#
# If a directory already exists at `path`, the behaviour is platform-dependent:
#
#  - On Windows, the directory will not be overwritten, and the resulting error
#    will have its code set to 'EPERM'.
#
#  - On Mac and Linux, the directory will be overwritten if and only if it is
#    empty.  Otherwise, the resulting error will have its code set to
#    'ENOTEMPTY'.
#
writeDirectory = (path, tmpDirPath, cb) =>
	tmpPath = Path.join tmpDirPath, generateId()

	Fs.mkdir tmpPath, (err) =>
		if err
			cb new IOError err
			return

		commit = (cb) =>
			Fs.rename tmpPath, path, (err) =>
				if err
					cb new IOError err
					return

				cb()

		cb null, tmpPath, new AtomicOperation(commit)


# Same as writeDirectory, without generating the unique folder name
# or providing the tempPath in the mkdir callback arguments

# TODO: Better name, or made part of writeDirectory API
writeDirectoryNormally = (path, tmpDirPath, cb) =>
	Fs.mkdir tmpDirPath, (err) =>
		if err
			cb new IOError err
			return

		commit = (cb) =>
			Fs.rename tmpDirPath, path, (err) =>
				if err
					cb new IOError err
					return

				cb()

		cb null, new AtomicOperation(commit)

# Atomically remove a directory tree at the specified path.
#
# This function acts like 'rm -rf', except that it is an atomic operation.
deleteDirectory = (path, tmpDirPath, cb) =>
	tmpPath = Path.join tmpDirPath, generateId()

	Async.series [
		(cb) =>
			Fs.rename path, tmpPath, (err) =>
				if err
					cb new IOError err
					return

				cb()
		(cb) =>
			Rimraf tmpPath, (err) =>
				if err
					cb new IOError err
					return

				cb()
	], cb

# AtomicOperation objects are returned by some of the above functions.
# They give the API user the opportunity to perform additional work before
# committing the operation.
#
# This class is not directly exposed to API users.
class AtomicOperation
	constructor: (@_doCommit) ->
		@isCommitted = false

	commit: (cb) =>
		if @isCommitted
			cb new Error "operation already committed"
			return

		@isCommitted = true

		@_doCommit cb

module.exports = {
	writeFile
	writeBufferToFile
	writeJSONToFile
	writeDirectory
	writeDirectoryNormally
	deleteDirectory
}
