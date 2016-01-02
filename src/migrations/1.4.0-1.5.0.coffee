Assert = require 'assert'
Async = require 'async'
Base64url = require 'base64url'
Fs = require 'fs'
Imm = require 'immutable'
Path = require 'path'
Moment = require 'moment'

{
	SymmetricEncryptionKey
	WeakSymmetricEncryptionKey
} = require '../persist/crypto'
{TimestampFormat} = require '../persist/utils'



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
			Async.eachSeries fileNames, (fileName, cb) ->
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



# //////////////// Version-Specific Utilities /////////////////


addContextFieldsToAllObjects = (dataDir, globalEncryptionKey, cb) ->
	# Check to see if migration step has already run
	Fs.readdir Path.join(dataDir, 'clientFiles'), (err, clientFiles) ->
		if err
			cb err
			return

		if clientFiles.length > 0 and clientFiles[0].indexOf('.') < 0
			# File names already seem to be encrypted,
			# so this step has probably been run too
			console.log("Skipping context field injection step.")
			cb()
			return

		Async.series [
			(cb) ->
				forEachFileIn Path.join(dataDir, 'clientFiles'), (clientFile, cb) ->
					clientFilePath = Path.join(dataDir, 'clientFiles', clientFile)

					forEachFileIn clientFilePath, (clientFileRev, cb) ->
						if clientFileRev is 'planTargets'
							forEachFileIn Path.join(clientFilePath, 'planTargets'), (planTarget, cb) ->
								planTargetPath = Path.join(clientFilePath, 'planTargets', planTarget)

								forEachFileIn planTargetPath, (planTargetRev, cb) ->
									objPath = Path.join(planTargetPath, planTargetRev)

									addContextFieldsToObject objPath, dataDir, globalEncryptionKey, cb
								, cb
							, cb
							return

						if clientFileRev is 'progEvents'
							forEachFileIn Path.join(clientFilePath, 'progEvents'), (progEvent, cb) ->
								progEventPath = Path.join(clientFilePath, 'progEvents', progEvent)

								forEachFileIn progEventPath, (progEventRev, cb) ->
									objPath = Path.join(progEventPath, progEventRev)

									addContextFieldsToObject objPath, dataDir, globalEncryptionKey, cb
								, cb
							, cb
							return

						if clientFileRev is 'progNotes'
							forEachFileIn Path.join(clientFilePath, 'progNotes'), (progNote, cb) ->
								progNotePath = Path.join(clientFilePath, 'progNotes', progNote)

								forEachFileIn progNotePath, (progNoteRev, cb) ->
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
				forEachFileIn Path.join(dataDir, 'metrics'), (metric, cb) ->
					metricPath = Path.join(dataDir, 'metrics', metric)

					forEachFileIn metricPath, (metricRev, cb) ->
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



updateProgNote = (dataDir, globalEncryptionKey, clientFilePlan, progNote, progNotePath, cb) ->
	# No changes required for Quick Notes, skip!
	if progNote.get('type') isnt 'full'
		console.log "Skipping 'basic' progNote (Quick Note)"
		cb()
		return

	# Otherwise, looks like we have a 'full' progNote to update :)

	Async.series [
		# First, change the 'full' progNote key 'sections' to 'units'
		(cb) ->									
			progNote = progNote.mapKeys (key) -> 
				switch key
					when 'sections'
						console.log "Changing key name 'sections' to 'units'"
						return 'units'
					when 'units'
						console.warn "progNote already has 'sections' named as 'units'"
						return key
					else
						return key

			console.log "progNote with new key name:", progNote.toJS()
			cb()

		(cb) ->
			# Map units over to the new format
			# -> targets mapped into appropriate sections
			newUnits = progNote.get('units').map (unit) ->
				if not unit.has('sections') and unit.get('targets')?

					# Use clientFilePlan sections as our template
					unitPlanSections = clientFilePlan.get('sections').map (planSection) ->
						console.log "planSection", planSection.toJS()

						# Push in the appropriate targetNote objects to this section
						# by cross-referencing against targetIds in the planSection
						relatedTargets = Imm.List()
						unit.get('targets').forEach (target) ->
							if planSection.get('targetIds').contains target.get('id')
								relatedTargets = relatedTargets.push target

						console.log "relatedTargets", relatedTargets.toJS()

						# Return 'undefined' if no related targets (section didn't exist yet)
						if relatedTargets.isEmpty()
							console.warn "No progNote targets found related to this section, skipping!"
							return

						# Return planSection as a unitPlanSection w/ targets
						return planSection
						.delete('targetIds')
						.set('targets', relatedTargets)


					console.log "NEW unitPlanSections", unitPlanSections

					# Filter out any 'undefined' sections
					unitPlanSections = unitPlanSections.filter (section) -> section?

					# Return unit with new 'sections' property
					return unit
					.delete('targets')
					.set('sections', unitPlanSections)

				else
					console.log "Skipping progNote unit:", unit.toJS()
					return unit

			console.info "newUnits:", newUnits.toJS()

			# Apply new units array to progNote
			progNote = progNote.set('units', newUnits)
			cb()

		# Encrypt to buffer, save progNote revision
		(cb) ->
			newBuffer = globalEncryptionKey.encrypt JSON.stringify progNote

			Fs.writeFile progNotePath, newBuffer, (err) ->
				if err
					console.error "Problem writing progNote", err
					cb err
					return

				console.log "Wrote updatedProgNote to #{progNotePath}"
				cb()

	], (err) ->
		if err
			cb err
			return

		console.log "Finished updating 'full' progNote"
		cb()



updateAllProgNotes = (dataDir, globalEncryptionKey, cb) ->
	forEachFileIn Path.join(dataDir, 'clientFiles'), (clientFileDir, cb) ->
		clientFileDirPath = Path.join(dataDir, 'clientFiles', clientFileDir)

		clientFilePlan = null

		Async.series [
			# 1. Get 'plan' from latest revision of clientFile
			(cb) ->
				console.log "Getting #{clientFileDir} 'plan'"							

				getLatestRevision clientFileDirPath, globalEncryptionKey, (err, revision) ->
					if err
						cb err
						return

					clientFilePlan = revision.get('plan')
					cb()

			# 2. Get all progNotes
			(cb) ->
				console.log "Getting #{clientFileDir} progNotes"
				progNotesParentDirPath = Path.join(clientFileDirPath, 'progNotes')

				# Loop through directories in progNotes container
				forEachFileIn progNotesParentDirPath, (progNotesDir, cb) ->
					progNotesDirPath = Path.join(progNotesParentDirPath, progNotesDir)

					# Loop through each progNote revision
					forEachFileIn progNotesDirPath, (progNoteRevision, cb) ->
						progNotePath = Path.join(progNotesDirPath, progNoteRevision)

						progNote = null

						# Read progNote
						readFileData progNotePath, globalEncryptionKey, (err, result) ->
							if err
								console.error "Problem reading progNote", err
								cb err
								return

							progNote = result

							# Update the progNote
							updateProgNote(
								dataDir, globalEncryptionKey, clientFilePlan,
								progNote, progNotePath, cb
							)

					, cb
				, cb
		], cb
	, cb

encryptAndUpdateFileName = (oldFilePath, globalEncryptionKey, cb) ->
	decodeOldStyleFileNameComponent = (s) ->
		s = s.replace /%%([a-fA-F0-9]{4})/g, (match, hex) ->
			return String.fromCharCode parseInt(hex, 16)
		s = s.replace /%([a-fA-F0-9]{2})/g, (match, hex) ->
			return String.fromCharCode parseInt(hex, 16)
		return s

	parentDirPath = Path.dirname oldFilePath
	oldFileName = Path.basename oldFilePath

	fileNameComps = (decodeOldStyleFileNameComponent(c) for c in oldFileName.split('.'))
	newFileName = encryptFileName fileNameComps, globalEncryptionKey

	newFilePath = Path.join(parentDirPath, newFileName)

	Fs.rename oldFilePath, newFilePath, cb

encryptAllFileNames = (dataDir, globalEncryptionKey, cb) ->
	key = new WeakSymmetricEncryptionKey globalEncryptionKey, 5

	# Check to see if migration step has already run
	Fs.readdir Path.join(dataDir, 'clientFiles'), (err, clientFiles) ->
		if err
			cb err
			return

		if clientFiles.length > 0 and clientFiles[0].indexOf('.') < 0
			# File names already seem to be encrypted
			console.log("Skipping file name encryption step.")
			cb()
			return

		Async.series [
			(cb) ->
				forEachFileIn Path.join(dataDir, 'clientFiles'), (clientFile, cb) ->
					clientFilePath = Path.join(dataDir, 'clientFiles', clientFile)

					Async.series [
						(cb) ->
							forEachFileIn clientFilePath, (clientFileRev, cb) ->
								if clientFileRev is 'planTargets'
									forEachFileIn Path.join(clientFilePath, 'planTargets'), (planTarget, cb) ->
										planTargetPath = Path.join(clientFilePath, 'planTargets', planTarget)

										Async.series [
											(cb) ->
												forEachFileIn planTargetPath, (planTargetRev, cb) ->
													encryptAndUpdateFileName(
														Path.join(planTargetPath, planTargetRev),
														globalEncryptionKey, cb
													)
												, cb
											(cb) ->
												encryptAndUpdateFileName planTargetPath, globalEncryptionKey, cb
										], cb
									, cb
									return

								if clientFileRev is 'progEvents'
									forEachFileIn Path.join(clientFilePath, 'progEvents'), (progEvent, cb) ->
										progEventPath = Path.join(clientFilePath, 'progEvents', progEvent)

										Async.series [
											(cb) ->
												forEachFileIn progEventPath, (progEventRev, cb) ->
													encryptAndUpdateFileName(
														Path.join(progEventPath, progEventRev),
														globalEncryptionKey, cb
													)
												, cb
											(cb) ->
												encryptAndUpdateFileName progEventPath, globalEncryptionKey, cb
										], cb
									, cb
									return

								if clientFileRev is 'progNotes'
									forEachFileIn Path.join(clientFilePath, 'progNotes'), (progNote, cb) ->
										progNotePath = Path.join(clientFilePath, 'progNotes', progNote)

										Async.series [
											(cb) ->
												forEachFileIn progNotePath, (progNoteRev, cb) ->
													encryptAndUpdateFileName(
														Path.join(progNotePath, progNoteRev),
														globalEncryptionKey, cb
													)
												, cb
											(cb) ->
												encryptAndUpdateFileName progNotePath, globalEncryptionKey, cb
										], cb
									, cb
									return

								encryptAndUpdateFileName(
									Path.join(clientFilePath, clientFileRev),
									globalEncryptionKey, cb
								)
							, cb
						(cb) ->
							encryptAndUpdateFileName clientFilePath, globalEncryptionKey, cb
					], cb
				, cb
			(cb) ->
				forEachFileIn Path.join(dataDir, 'metrics'), (metric, cb) ->
					metricPath = Path.join(dataDir, 'metrics', metric)

					Async.series [
						(cb) ->
							forEachFileIn metricPath, (metricRev, cb) ->
								encryptAndUpdateFileName(
									Path.join(metricPath, metricRev),
									globalEncryptionKey, cb
								)
							, cb
						(cb) ->
							encryptAndUpdateFileName metricPath, globalEncryptionKey, cb
					], cb
				, cb
		], cb

addProgNoteStatusFields = (dataDir, globalEncryptionKey, cb) ->
	forEachFileIn Path.join(dataDir, 'clientFiles'), (clientFile, cb) ->
		clientFilePath = Path.join(dataDir, 'clientFiles', clientFile)

		forEachFileIn Path.join(clientFilePath, 'progNotes'), (progNote, cb) ->
			progNotePath = Path.join(clientFilePath, 'progNotes', progNote)

			progNoteObjectFilePath = null
			progNoteObject = null

			Async.series [
				(cb) ->
					Fs.readdir progNotePath, (err, revisions) ->
						if err
							cb err
							return

						Assert.equal revisions.length, 1, 'should always be exactly one progNote revision'
						progNoteObjectFilePath = Path.join(progNotePath, revisions[0])

						cb()
				(cb) ->
					Fs.readFile progNoteObjectFilePath, (err, result) ->
						if err
							cb err
							return

						progNoteObject = JSON.parse globalEncryptionKey.decrypt result

						cb()
				(cb) ->
					progNoteObject.status = 'default'
					encryptedObj = globalEncryptionKey.encrypt JSON.stringify progNoteObject

					Fs.writeFile progNoteObjectFilePath, encryptedObj, cb
			], cb
			
		, cb
	, cb

addProgEventTypeIdField = (dataDir, globalEncryptionKey, cb) ->
	forEachFileIn Path.join(dataDir, 'clientFiles'), (clientFile, cb) ->
		clientFilePath = Path.join(dataDir, 'clientFiles', clientFile)

		forEachFileIn Path.join(clientFilePath, 'progEvents'), (progEvent, cb) ->
			progEventPath = Path.join(clientFilePath, 'progEvents', progEvent)

			progEventObjectFilePath = null
			progEventObject = null

			Async.series [
				(cb) =>
					Fs.readdir progEventPath, (err, revisions) ->
						if err
							cb err
							return

						Assert.equal revisions.length, 1, 'should always be exactly one progEvent revision'
						progEventObjectFilePath = Path.join(progEventPath, revisions[0])

						cb()
				(cb) =>
					Fs.readFile progEventObjectFilePath, (err, result) ->
						if err
							cb err
							return

						progEventObject = JSON.parse globalEncryptionKey.decrypt result

						cb()
				(cb) =>
					progEventObject.typeId = ''
					encryptedObj = globalEncryptionKey.encrypt JSON.stringify progEventObject

					Fs.writeFile progEventObjectFilePath, encryptedObj, cb
			], cb

		, cb
	, cb

	addProgEventStatusField = (dataDir, globalEncryptionKey, cb) ->
		forEachFileIn Path.join(dataDir, 'clientFiles'), (clientFile, cb) ->
			clientFilePath = Path.join(dataDir, 'clientFiles', clientFile)

			forEachFileIn Path.join(clientFilePath, 'progEvents'), (progEvent, cb) ->
				progEventPath = Path.join(clientFilePath, 'progEvents', progEvent)

				progEventObjectFilePath = null
				progEventObject = null

				Async.series [
					(cb) =>
						Fs.readdir progEventPath, (err, revisions) ->
							if err
								cb err
								return

							Assert.equal revisions.length, 1, 'should always be exactly one progEvent revision'
							progEventObjectFilePath = Path.join(progEventPath, revisions[0])

							cb()
					(cb) =>
						Fs.readFile progEventObjectFilePath, (err, result) ->
							if err
								cb err
								return

							progEventObject = JSON.parse globalEncryptionKey.decrypt result

							cb()
					(cb) =>
						progEventObject.status = 'default'
						encryptedObj = globalEncryptionKey.encrypt JSON.stringify progEventObject

						Fs.writeFile progEventObjectFilePath, encryptedObj, cb
				], cb

			, cb
		, cb



# ////////////////////// Migration Series //////////////////////


module.exports = {
	run: (dataDir, userName, password, cb) ->
		globalEncryptionKey = null

		Async.series [

			# Global Encryption Key
			(cb) ->
				console.groupCollapsed "1. Load global encryption key"
				loadGlobalEncryptionKey dataDir, userName, password, (err, result) ->
					if err
						console.error "Problem loading encryption key", err
						cb err
						return

					globalEncryptionKey = result
					cb()

			# Add Context Fields to all objects (issue#191)
			(cb) ->
				console.groupEnd()
				console.groupCollapsed "2. Add context fields to all objects"
				addContextFieldsToAllObjects dataDir, globalEncryptionKey, cb

			# New Directory: 'programs'
			(cb) ->
				console.groupEnd()
				console.groupCollapsed "3. Create 'programs' directory"
				createEmptyDirectory dataDir, 'programs', cb

			# New Directory: 'clientFileProgramLinks'
			(cb) ->
				console.groupEnd()
				console.groupCollapsed "4. Create 'clientFileProgramLinks' directory"
				createEmptyDirectory dataDir, 'clientFileProgramLinks', cb

			# Improvements for progNote Schema (issue#7)
			(cb) ->
				console.groupEnd()
				console.groupCollapsed "5. Update progNote format, map plan sections into 'full' units"
				updateAllProgNotes dataDir, globalEncryptionKey, cb

			# Encrypt indexed fields (issue#309)
			(cb) ->
				console.groupEnd()
				console.groupCollapsed "6. Encrypt indexed fields"
				encryptAllFileNames dataDir, globalEncryptionKey, cb

			# Add status fields to progNotes
			(cb) ->
				console.groupEnd()
				console.groupCollapsed "7. Add 'status': 'default' field to progress notes"
				addProgNoteStatusFields dataDir, globalEncryptionKey, cb

			# New Directory: 'eventTypes' (issue#347)
			(cb) ->
				console.groupEnd()
				console.groupCollapsed "8. Create 'eventTypes' directory"
				createEmptyDirectory dataDir, 'eventTypes', cb

			# Add typeId field to progEvents
			(cb) ->
				console.groupEnd()
				console.groupCollapsed "9. Add 'typeId' field to progress events"
				addProgEventTypeIdField dataDir, globalEncryptionKey, cb

			# Add status field to progEvents
			(cb) ->
				console.groupEnd()
				console.groupCollapsed "10. Add 'status': 'default' field to progress events"
				addProgEventStatusField dataDir, globalEncryptionKey, cb

		], (err) ->
			if err
				cb err
				return

			console.groupEnd()
			cb()
}
