Assert = require 'assert'
Async = require 'async'
Base64url = require 'base64url'
Fs = require 'fs'
Imm = require 'immutable'
Path = require 'path'
Moment = require 'moment'

{SymmetricEncryptionKey, PrivateKey, PublicKey} = require '../persist/crypto'
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


# //////////////// Version-Specific Utilities /////////////////


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


updateProgNoteFormat = (dataDir, globalEncryptionKey, cb) ->
	forEachFile Path.join(dataDir, 'clientFiles'), (clientFileDir, cb) ->
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
				forEachFile progNotesParentDirPath, (progNotesDir, cb) ->
					progNotesDirPath = Path.join(progNotesParentDirPath, progNotesDir)

					# Loop through each progNote revision
					forEachFile progNotesDirPath, (progNoteRevision, cb) ->
						progNoteRevisionPath = Path.join(progNotesDirPath, progNoteRevision)

						progNote = null

						# Read progNote
						readFileData progNoteRevisionPath, globalEncryptionKey, (err, result) ->
							if err
								console.error "Problem reading progNote", err
								cb err
								return

							progNote = result

							# No changes required for Quick Notes, skip!
							if progNote.get('type') isnt 'full'
								console.log "Skipping 'basic' progNote (Quick Note)"
								cb()
								return


							# Otherwise, looks like we have a 'full' progNote to update :)

							Async.series [
								# First, change the 'full' progNote key 'sections' to 'units'
								(cb) ->									
									progNote = result.mapKeys (key) -> 
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

									Fs.writeFile progNoteRevisionPath, newBuffer, (err) ->
										if err
											console.error "Problem writing progNote", err
											cb err
											return

										console.log "Wrote updatedProgNote to #{progNoteRevisionPath}"
										cb()

							], (err) ->
								if err
									cb err
									return

								console.log "Finished updating 'full' progNote"
								cb()

					, cb
				, cb
		], cb
	, cb


# ////////////////////// Migration Series //////////////////////

module.exports = {
	run: (dataDir, userName, password, cb) ->
		globalEncryptionKey = null

		Async.series [

			# Global Encryption Key
			(cb) ->
				console.info "1. Load global encryption key..."
				loadGlobalEncryptionKey dataDir, userName, password, (err, result) ->
					if err
						console.error "Problem loading encryption key", err
						cb err
						return

					globalEncryptionKey = result
					cb()

			# Add Context Fields to all objects
			(cb) ->
				console.info "2. Add context fields to all objects..."
				addContextFieldsToAllObjects dataDir, globalEncryptionKey, cb

			# New Directory: 'programs'
			(cb) ->
				console.info "3. Create 'programs' directory"
				createEmptyDirectory dataDir, 'programs', cb

			# New Directory: 'clientFileProgramLinks'
			(cb) ->
				console.info "4. Create 'clientFileProgramLinks' directory"
				createEmptyDirectory dataDir, 'clientFileProgramLinks', cb

			# Improvements for progNote Schema (issue#7)
			(cb) ->
				console.info "5. Update progNote format, map plan sections into 'full' units"
				updateProgNoteFormat dataDir, globalEncryptionKey, cb

		], cb
}