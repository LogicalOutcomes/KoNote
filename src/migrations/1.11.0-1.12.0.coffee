Assert = require 'assert'
Async = require 'async'
Base64url = require 'base64url'
Fs = require 'fs'
Imm = require 'immutable'
Path = require 'path'
Moment = require 'moment'

{SymmetricEncryptionKey, WeakSymmetricEncryptionKey} = require '../persist/crypto'
{TimestampFormat} = require '../persist/utils'

lastMigrationStep = 0

# /////////////////// Generic Utilities ///////////////////


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
						cb new Error "Unknown Username"
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
					cb new Error "Incorrect Password"
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

		console.log "Finished loading encryption key!"

		globalEncryptionKey = SymmetricEncryptionKey.import privateInfo.globalEncryptionKey
		cb null, globalEncryptionKey

forEachFileIn = (parentDir, loopBody, cb) ->
	console.group("For each file in #{JSON.stringify parentDir}:")

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
			if fileNames.length is 0
				console.warn "(no files to iterate over)"
				cb()
				return

			Async.eachSeries fileNames, (fileName, cb) ->
				# Skip .DS_Store & Thumbs.db files, and known children folders
				# TODO: Make this a regex check
				if fileName in ['.DS_Store', 'Thumbs.db', 'progEvents', 'planTargets', 'progNotes', 'alerts']
					console.warn "Skipping #{fileName}"
					cb()
					return

				console.group "Process #{JSON.stringify Path.join(parentDir, fileName)}:"

				loopBody fileName, (err) ->
					if err
						cb err
						return

					console.groupEnd()

					cb()
			, cb
	], (err) ->
		if err
			cb err
			return

		console.groupEnd()

		cb()

createEmptyDirectory = (parentPath, dirName, cb) ->
	newDirPath = Path.join parentPath, dirName

	Fs.mkdir newDirPath, (err) ->
		if err
			if err.code is 'EEXIST'
				console.error "Directory #{newDirPath} already exists", err
				cb()
				return

			cb err
			return

		console.log "Created new directory '#{dirName}' at: #{newDirPath}"
		cb()

readFileData = (filePath, globalEncryptionKey, cb) ->
	console.log "Reading file: '#{filePath}'"

	Fs.readFile filePath, (err, buffer) ->
		if err
			if err.code is 'EISDIR'
				console.warn "Skipping directory: '#{filePath}'"
				cb()
				return

			cb err
			return

		fileData = JSON.parse globalEncryptionKey.decrypt buffer
		cb null, Imm.fromJS(fileData)

getAllRevisions = (dirPath, globalEncryptionKey, cb) ->
	console.log "Getting all revisions in #{dirPath}"

	filesList = null
	revisions = null

	Async.series [
		(cb) ->
			console.log "dirPath", dirPath
			Fs.readdir dirPath, (err, result) ->
				if err
					if err.code is 'ENOENT'
						console.error "'#{dirPath}' does exist.", err
					cb err
					return

				filesList = result
				cb()

		(cb) ->
			Async.map filesList, (file, cb) ->
				console.log "Reading #{file}"

				filePath = Path.join(dirPath, file)
				readFileData filePath, globalEncryptionKey, cb
			, (err, results) ->
				if err
					cb err
					return

				revisions = Imm.List(results)
				.filter (result) -> result? # Strip out folders (undefined)
				.sortBy (result) -> Moment(result.get('timestamp'), TimestampFormat)

				cb()

	], (err) ->
		if err
			cb err
			return

		cb null, revisions

getLatestRevision = (dirPath, globalEncryptionKey, cb) ->
	console.log "Getting latest revision for #{dirPath}"
	getAllRevisions dirPath, globalEncryptionKey, (err, results) ->
		if err
			cb err
			return

		latestRevision = results.last()
		cb null, latestRevision

# Encrypts the specified file name components, and returns a suitable file name.
# components should be an array of strings, consisting of the indexed field
# values, followed by the object's ID.
encryptFileName = (components, globalEncryptionKey) ->
	encodeFileName = (components) ->
		delimiter = new Buffer([0x00, 0x53])

		result = []

		for c, i in components
			if i > 0
				result.push delimiter

			encodedComp = encodeFileNameComponent(c)
			result.push encodedComp

		return Buffer.concat result

	encodeFileNameComponent = (comp) ->
		unless Buffer.isBuffer comp
			throw new Error "expected file name component to be a buffer"

		literalNulByte = new Buffer([0x00, 0x4C])

		result = []

		for i in [0...comp.length]
			# If the byte needs to be encoded specially
			if comp[i] is 0x00
				result.push literalNulByte
				continue

			# This is probably pretty inefficient...
			result.push comp.slice(i, i+1)

		return Buffer.concat result

	key = new WeakSymmetricEncryptionKey globalEncryptionKey, 5

	encodedFileName = encodeFileName(
		components.map (comp, compIndex) ->
			if compIndex is (components.length - 1)
				return Base64url.toBuffer comp

			return new Buffer(comp, 'utf8')
	)
	return Base64url.encode key.encrypt encodedFileName

# Decrypts the specified file name into the specified number of components.
# componentCount should equal the number of indexed fields + 1.
# Returns an array of strings.
# A typical return value might look like: [indexedField1, indexedField2, id]
decryptFileName = (encryptedFileName, componentCount, globalEncryptionKey) ->
	createZeroedBuffer = (bufferSize) ->
		result = new Buffer(bufferSize)

		for i in [0...bufferSize]
			result[i] = 0

		return result

	key = new WeakSymmetricEncryptionKey globalEncryptionKey, 5
	fileName = key.decrypt Base64url.toBuffer encryptedFileName

	comps = []

	nextComp = createZeroedBuffer(fileName.length)
	nextCompOffset = 0
	i = 0
	while i < fileName.length
		# If the next byte is a special sequence
		if fileName[i] is 0x00
			# If no more bytes in the file name
			if i is (fileName.length - 1)
				# There must always be another byte following a dot
				throw new Error "file name ended early: #{fileName.toJSON()}"

			switch fileName[i+1]
				when 0x4C # "L"
					# Add literal NUL byte to component
					nextComp[nextCompOffset] = 0x00
					nextCompOffset += 1
				when 0x53 # "S"
					# Found a separator, time to start on the next component

					# Add this component to result list
					comps.push nextComp.slice(0, nextCompOffset)

					# Reset for next component
					nextComp = createZeroedBuffer(fileName.length)
					nextCompOffset = 0
				else
					throw new Error "unexpected byte sequence at #{i} in file name: #{fileName.toJSON()}"

			# Skip over the next byte, since we already handled it
			i += 2
			continue

		nextComp[nextCompOffset] = fileName[i]
		nextCompOffset += 1

		i += 1

	# Add the last component to the result list
	comps.push nextComp.slice(0, nextCompOffset)

	if comps.length isnt componentCount
		console.log fileName
		throw new Error "expected #{componentCount} parts in file name #{JSON.stringify comps}"

	[indexedFields..., id] = comps
	indexedFields = indexedFields.map (buf) -> buf.toString()
	id = Base64url.encode id
	return [indexedFields..., id]

finalizeMigrationStep = (dataDir, cb=(->)) ->
	versionPath = Path.join dataDir, 'version.json'
	versionData = null

	Async.series [
		(cb) ->
			Fs.readFile versionPath, (err, result) ->
				if err
					cb err
					return

				versionData = JSON.parse result
				cb()
		(cb) ->
			# Increment lastMigrationStep, and save back to version.json
			lastMigrationStep++
			versionData.lastMigrationStep = lastMigrationStep

			Fs.writeFile versionPath, JSON.stringify(versionData), (err) ->
				if err
					cb err
					return

				console.log "Updated version lastMigrationStep to #{lastMigrationStep}"
				cb()
	], cb


# //////////////// Version-Specific Utilities /////////////////

addPlanTemplateDescriptionField = (dataDir, globalEncryptionKey, cb) ->
	forEachFileIn Path.join(dataDir, 'planTemplates'), (planTemplate, cb) ->
		planTemplateDirPath = Path.join(dataDir, 'planTemplates', planTemplate)

		forEachFileIn planTemplateDirPath, (planTemplateRev, cb) ->
			planTemplateRevPath = Path.join(planTemplateDirPath, planTemplateRev)
			planTemplateRevObject = null

			Async.series [
				(cb) =>
					# Read planTemplate object
					Fs.readFile planTemplateRevPath, (err, result) ->
						if err
							cb err
							return

						planTemplateRevObject = JSON.parse globalEncryptionKey.decrypt result

						cb()
				(cb) =>
					# Add 'description' property
					planTemplateRevObject.description = ' '
					encryptedObj = globalEncryptionKey.encrypt(JSON.stringify planTemplateRevObject)
					Fs.writeFile planTemplateRevPath, encryptedObj, cb
			], cb
		, cb
	, (err) ->
		if err
			console.info "Problem with planTemplate desc"
			cb err
			return

		finalizeMigrationStep(dataDir, cb)


addClientFileBirthDateField = (dataDir, globalEncryptionKey, cb) ->
	forEachFileIn Path.join(dataDir, 'clientFiles'), (clientFile, cb) ->
		clientFileDirPath = Path.join(dataDir, 'clientFiles', clientFile)

		forEachFileIn clientFileDirPath, (clientFileRev, cb) ->
			clientFileRevPath = Path.join(clientFileDirPath, clientFileRev)
			clientFileRevObject = null

			Async.series [
				(cb) =>
					# Read clientFile object
					Fs.readFile clientFileRevPath, (err, result) ->
						if err
							cb err
							return

						clientFileRevObject = JSON.parse globalEncryptionKey.decrypt result

						cb()
				(cb) =>
					# Add 'birthDate' property
					clientFileRevObject.birthDate = ''
					encryptedObj = globalEncryptionKey.encrypt(JSON.stringify clientFileRevObject)
					Fs.writeFile clientFileRevPath, encryptedObj, cb
			], cb
		, cb
	, (err) ->
		if err
			console.info "Problem with clientFile birthday"
			cb err
			return

		finalizeMigrationStep(dataDir, cb)


createClientFileAttachmentsDirs = (dataDir, globalEncryptionKey, cb) ->
	forEachFileIn Path.join(dataDir, 'clientFiles'), (clientFile, cb) ->
		clientFileDirPath = Path.join(dataDir, 'clientFiles', clientFile)

		createEmptyDirectory clientFileDirPath, 'attachments', cb

	, (err) ->
		if err
			console.info "Problem with adding attachments dirs"
			cb err
			return

		finalizeMigrationStep(dataDir, cb)


# ////////////////////// Migration Series //////////////////////

module.exports = {
	run: (dataDir, userName, password, lastMigrationStep, cb) ->
		globalEncryptionKey = null

		# This is where we add the migration series steps
		migrationSeries = [

			(cb) ->
				console.groupEnd()
				console.groupCollapsed "1. Add 'description': ' ' field to plan template objects"
				addPlanTemplateDescriptionField dataDir, globalEncryptionKey, cb

			(cb) ->
				console.groupEnd()
				console.groupCollapsed "2. Add 'birthDate': '' field to clientFile objects"
				addClientFileBirthDateField dataDir, globalEncryptionKey, cb

			(cb) ->
				console.groupEnd()
				console.groupCollapsed "3. Create 'attachments' dir in each clientFile"
				createClientFileAttachmentsDirs dataDir, globalEncryptionKey, cb

		]


		# Slice off the previous steps for a partial migration
		if lastMigrationStep?
			migrationSeries = migrationSeries.slice(lastMigrationStep)

		# Shift in standard step
		migrationSeries.unshift (cb) ->
			console.groupCollapsed "0. Load global encryption key"
			loadGlobalEncryptionKey dataDir, userName, password, (err, result) ->
				if err
					cb err
					return

				globalEncryptionKey = result
				cb()

		# Execute the series
		Async.series migrationSeries, (err) ->
			if err
				cb err
				return

			# End series log groups, write dataVersion before finishing
			console.groupEnd()
			cb()
}