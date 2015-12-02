Assert = require 'assert'
Async = require 'async'
Base64url = require 'base64url'
Fs = require 'fs'
Imm = require 'immutable'
Path = require 'path'

{SymmetricEncryptionKey, PrivateKey, PublicKey} = require '../persist/crypto'

# BEGIN utility functions

loadGlobalEncryptionKey = (dataDir, userName, password, cb) =>
	userDir = Path.join(dataDir, '_users', userName)

	accountKeyId = null
	accountKeyInfo = null
	accountKey = null
	privateInfo = null
	accountType = null
	decryptedAccount = null

	Async.series [
		(cb) ->
			Fs.readdir userDir, (err, fileNames) ->
				if err
					if err.code is 'ENOENT'
						cb new UnknownUserNameError()
						return

					cb err
					return

				# Find the highest (i.e. most recent) account key ID
				accountKeyId = Imm.List(fileNames)
				.filter (fileName) ->
					return fileName.startsWith 'account-key-'
				.map (fileName) ->
					return Number(fileName['account-key-'.length...])
				.max()

				cb()
		(cb) ->
			Fs.readFile Path.join(userDir, "account-key-#{accountKeyId}"), (err, buf) ->
				if err
					cb err
					return

				accountKeyInfo = JSON.parse buf
				cb()
		(cb) ->
			SymmetricEncryptionKey.derive password, accountKeyInfo.kdfParams, (err, result) ->
				if err
					cb err
					return

				pwEncryptionKey = result

				# Use password to decrypt account key
				encryptedAccountKey = Base64url.toBuffer(accountKeyInfo.accountKey)
				try
					accountKeyBuf = pwEncryptionKey.decrypt(encryptedAccountKey)
				catch err
					console.error err.stack

					# If decryption fails, we're probably using the wrong key
					cb new IncorrectPasswordError()
					return

				accountKey = SymmetricEncryptionKey.import(accountKeyBuf.toString())

				cb()
		(cb) =>
			Fs.readFile Path.join(userDir, 'private-info'), (err, buf) ->
				if err
					cb err
					return

				privateInfo = JSON.parse accountKey.decrypt buf
				cb()
	], (err) =>
		if err
			cb err
			return

		globalEncryptionKey = SymmetricEncryptionKey.import privateInfo.globalEncryptionKey
		cb null, globalEncryptionKey

forEachFile = (parentDir, loopBody, cb) ->
	console.log("For each file in #{JSON.stringify parentDir}:")

	fileNames = null

	Async.series [
		(cb) ->
			Fs.readdir parentDir, (err, result) ->
				if err
					cb err
					return

				fileNames = result
				cb()
		(cb) ->
			Async.eachSeries fileNames, (fileName, cb) ->
				console.log("Processing #{JSON.stringify Path.join(parentDir, fileName)}.")

				loopBody fileName, cb
			, cb
	], (err) ->
		if err
			cb err
			return

		console.log("Done iterating files in #{JSON.stringify parentDir}.")

		cb()

# END utility functions

# BEGIN version-specific code

module.exports = {
	run: (dataDir, userName, password, cb) ->
		globalEncryptionKey = null

		Async.series [
			(cb) ->
				loadGlobalEncryptionKey dataDir, userName, password, (err, result) ->
					if err
						cb err
						return

					globalEncryptionKey = result
					cb()
			(cb) ->
				addContextFieldsToAllObjects dataDir, globalEncryptionKey, cb
		], cb
}

addContextFieldsToAllObjects = (dataDir, globalEncryptionKey, cb) ->
	Async.series [
		(cb) ->
			forEachFile Path.join(dataDir, 'clientFiles'), (clientFile, cb) ->
				clientFilePath = Path.join(dataDir, 'clientFiles', clientFile)

				forEachFile clientFilePath, (clientFileRev, cb) ->
					if clientFileRev is 'planTargets'
						forEachFile Path.join(clientFilePath, 'planTargets'), (planTarget, cb) ->
							planTargetPath = Path.join(clientFilePath, 'planTargets', planTarget)

							forEachFile planTargetPath, (planTargetRev, cb) ->
								objPath = Path.join(planTargetPath, planTargetRev)

								addContextFieldsToObject objPath, dataDir, globalEncryptionKey, cb
							, cb
						, cb
						return

					if clientFileRev is 'progEvents'
						forEachFile Path.join(clientFilePath, 'progEvents'), (progEvent, cb) ->
							progEventPath = Path.join(clientFilePath, 'progEvents', progEvent)

							forEachFile progEventPath, (progEventRev, cb) ->
								objPath = Path.join(progEventPath, progEventRev)

								addContextFieldsToObject objPath, dataDir, globalEncryptionKey, cb
							, cb
						, cb
						return

					if clientFileRev is 'progNotes'
						forEachFile Path.join(clientFilePath, 'progNotes'), (progNote, cb) ->
							progNotePath = Path.join(clientFilePath, 'progNotes', progNote)

							forEachFile progNotePath, (progNoteRev, cb) ->
								objPath = Path.join(progNotePath, progNoteRev)

								addContextFieldsToObject objPath, dataDir, globalEncryptionKey, cb
							, cb
						, cb
						return

					objPath = Path.join(clientFilePath, clientFileRev)

					addContextFieldsToObject objPath, dataDir, globalEncryptionKey, cb
				, cb
			, cb
		(cb) ->
			forEachFile Path.join(dataDir, 'metrics'), (metric, cb) ->
				metricPath = Path.join(dataDir, 'metrics', metric)

				forEachFile metricPath, (metricRev, cb) ->
					objPath = Path.join(metricPath, metricRev)

					addContextFieldsToObject objPath, dataDir, globalEncryptionKey, cb
				, cb
			, cb
	], cb

addContextFieldsToObject = (objFilePath, dataDir, globalEncryptionKey, cb) ->
	# Figure out the object's context
	objDir = Path.relative(dataDir, Path.dirname objFilePath)
	objDirParts = objDir.split(Path.sep)

	Assert objDirParts.length % 2 is 0, "even number of parent dirs needed"

	objCollectionName = objDirParts[objDirParts.length - 2]
	objContextDirParts = objDirParts[...-2]

	# Extract context information from the file path
	contextCollectionNames = []
	contextIds = []
	for objDirPart, i in objContextDirParts
		if i % 2 is 0
			contextCollectionNames.push objDirPart
		else
			indexedFields = objDirPart.split('.')
			objId = indexedFields[indexedFields.length - 1]
			contextIds.push objId

	obj = null

	Async.series [
		(cb) ->
			Fs.readFile objFilePath, (err, result) ->
				if err
					cb err
					return

				obj = JSON.parse globalEncryptionKey.decrypt result
				cb()
		(cb) ->
			obj._collectionName = objCollectionName
			obj._contextCollectionNames = contextCollectionNames
			obj._contextIds = contextIds

			encryptedObj = globalEncryptionKey.encrypt JSON.stringify obj

			Fs.writeFile objFilePath, encryptedObj, cb
	], cb

# END version-specific code
