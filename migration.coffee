# Tools for upgrading/downgrading a data directory from one version to another.
#
# This module is designed to accommodate both forward and backward migrations.
# Backward migrations (rollbacks) are sometimes needed if a customer runs into
# problems with a release and wishes to revert to an older version.
#
# Some guidelines for writing migration code:
#
# -	Log thoroughly.  Unlike most code, migration code is typically supervised
#	when run.  Console output is useful for seeing, e.g., which file caused the
#	migration to fail.
#
# -	Avoid parallel operations.  Being consistent and easy to follow is more
#	important here than speed.  Use Async.eachSeries, and Async.mapSeries.
#
# -	Rollbacks should not delete user data.  When migrating forward, it's
#	acceptable to delete data if it is determined that it is no longer needed.
#	Backwards migrations, however, might remove a feature that the customer was
#	using.  The data should be kept until they are able to upgrade again.
#
# - Keep migration code self-contained.  As much as possible, avoid using
#	functions from outside the migration.  Migrations code stays around
#	approximately forever, but everything around it can change.  To reduce the
#	risk of breakage and bit rot, it's best to keep migrations independent from
#	each other, and from their environment.

Async = require 'async'
Fs = require 'fs'
Imm = require 'immutable'
Path = require 'path'

{SymmetricEncryptionKey, PrivateKey, PublicKey} = require './persist/crypto'

# Use this at the command line
runMigration = (dataDir, fromVersion, toVersion, userName, password) ->
	migrate dataDir, fromVersion, toVersion, userName, password, (err) ->
		if err
			console.error "Migration failed:"
			console.error err
			console.error err.stack
			return

		console.log "Migration complete."

migrate = (dataDir, fromVersion, toVersion, userName, password, cb) ->
	# Eventually, this could be expanded to support migrating across many
	# versions (e.g. v1 -> v5).

	migration = migrations.find (migration) ->
		return migration.from is fromVersion and migration.to is toVersion

	unless migration
		cb new Error "could not find migration from #{fromVersion} to #{toVersion}"
		return

	console.log "Running migration step #{migration.from} -> #{migration.to}..."
	migration.run dataDir, userName, password, (err) ->
		if err
			cb err
			return

		console.log "Done migration step #{migration.from} -> #{migration.to}."
		cb()

migrations = Imm.List([
	{
		from: '1.3.0'
		to: '1.3.1'
		run: (dataDir, userName, password, cb) ->
			# TODO
			# elsewhere:
			# x deactivate
			# x decryptWithPassword
			# x decryptWithSystemKey + setPassword
			adminKdfParams = null
			adminPwEncryptionKey = null
			adminPrivateKeys = null

			userNames = null
			systemUserDir = Path.join(dataDir, '_users', '_system')
			weakSystemKey = null

			Async.series [
				(cb) ->
					console.log "Reading admin's auth-params"
					Fs.readFile Path.join(dataDir, '_users', userName, 'auth-params'), (err, result) ->
						if err
							cb err
							return

						adminKdfParams = JSON.parse result
						cb()
				(cb) ->
					console.log "Deriving key from admin password"
					SymmetricEncryptionKey.derive password, adminKdfParams, (err, result) ->
						if err
							cb err
							return

						adminPwEncryptionKey = result
						cb()
				(cb) ->
					console.log "Reading admin private keys"
					Fs.readFile Path.join(dataDir, '_users', userName, 'private-keys'), (err, result) ->
						if err
							cb err
							return

						adminPrivateKeys = JSON.parse adminPwEncryptionKey.decrypt result
						cb()
				(cb) ->
					console.log "Listing _users dir"
					Fs.readdir Path.join(dataDir, '_users'), (err, result) ->
						if err
							cb err
							return

						userNames = result
						cb()
				(cb) ->
					console.log "Generating system key"
					PrivateKey.generate (err, result) ->
						if err
							cb err
							return

						weakSystemKey = result
						cb()
				(cb) ->
					console.log "Creating system user dir"
					Fs.mkdir systemUserDir, cb
				(cb) ->
					console.log "Writing system public key"
					publicKeyPath = Path.join(systemUserDir, 'public-key')

					Fs.writeFile publicKeyPath, weakSystemKey.getPublicKey().export(), cb
				(cb) ->
					console.log "Writing old-key"
					privateKeyPath = Path.join(systemUserDir, 'old-key')
					globalEncryptionKey = SymmetricEncryptionKey.import(
						adminPrivateKeys.globalEncryptionKey
					)
					encryptedSystemKey = globalEncryptionKey.encrypt(weakSystemKey.export())

					# Temporary workaround: make the system key public until
					# all accounts are migrated to the new key escrow scheme.
					# Then the system key can be regenerated and kept private.
					Fs.writeFile privateKeyPath, encryptedSystemKey, cb
				(cb) ->
					console.log "Upgrading user accounts:"
					Async.eachSeries userNames, (userName, cb) ->
						userDir = Path.join(dataDir, '_users', userName)
						publicInfo = {isActive: true}

						console.log " - #{userDir}"

						Async.series [
							(cb) ->
								Fs.readFile Path.join(userDir, 'account-type'), (err, buf) ->
									if err
										cb err
										return

									publicInfo.accountType = JSON.parse buf
									cb()
							(cb) ->
								publicInfoPath = Path.join(userDir, 'public-info')

								Fs.writeFile publicInfoPath, JSON.stringify(publicInfo), cb
							(cb) ->
								Fs.unlink Path.join(userDir, 'account-type'), cb
						], cb
					, cb
			], cb
	}
	{
		from: '1.3.1'
		to: '1.4.0'
		run: (dataDir, userName, password, cb) ->
			# What are we creating? New empty value for backdate in each progNote
			# Get full list of progNotes
			# Loop through each progNote, add in the backdate
			# Overwrite progNotes

			clientFiles = null
			clientFileDirs = null

			adminKdfParams = null
			adminPwEncryptionKey = null
			adminPrivateKeys = null

			Async.series [
				# Getting admin authorization
				# (cb) ->
				# 	console.log "Reading admin's auth-params"
				# 	Fs.readFile Path.join(dataDir, '_users', userName, 'auth-params'), (err, result) ->
				# 		if err
				# 			cb err
				# 			return

				# 		adminKdfParams = JSON.parse result
				# 		cb()
				# (cb) ->
				# 	console.log "Deriving key from admin password"
				# 	SymmetricEncryptionKey.derive password, adminKdfParams, (err, result) ->
				# 		if err
				# 			cb err
				# 			return

				# 		adminPwEncryptionKey = result
				# 		cb()
				# (cb) ->
				# 	console.log "Reading admin private keys"
				# 	Fs.readFile Path.join(dataDir, '_users', userName, 'private-keys'), (err, result) ->
				# 		if err
				# 			cb err
				# 			return

				# 		adminPrivateKeys = JSON.parse adminPwEncryptionKey.decrypt result
				# 		cb()
				# Grab all progNotes for each clientFile
				(cb) ->
					console.log "Listing clientFiles dir"
					Fs.readdir Path.join(dataDir, 'clientFiles'), (err, result) ->
						if err
							cb err
							return

						clientFileDirs = result
						console.log "clientFileDirs", clientFileDirs
						cb()
				(cb) ->
					console.log "About to loop through each clientFile dir"

					Async.eachSeries clientFileDirs, (clientFile, cb) ->
						progNotesDir = Path.join(dataDir, 'clientFiles', clientFile, 'progNotes')

						console.info " - #{clientFile}"
						progNoteDirs = null

						Async.series [
							# Get list of progNote directories
							(cb) =>
								console.log "Listing progNotes directories"

								Fs.readdir progNotesDir, (err, result) ->
									if err
										cb err
										return

									progNoteDirs = result
									console.log "progNoteDirs", progNoteDirs
									
									cb()
							(cb) =>
								console.log "Read each progNote directory"

								# Loop through progNote directories
								Async.eachSeries progNoteDirs, (progNote, cb) ->					

									progNoteFiles = null
									progNoteFilePath = null
									progNoteFolders = null

									progNoteDir = Path.join(progNotesDir, progNote)
									console.log "Added directory name to path + ", progNote

									console.log "progNoteDir", progNoteDir

									Async.series [
										(cb) =>
											console.log "About to read progNote dir...."
											# Read the names of progNote folders
											Fs.readdir progNoteDir, (err, result) ->
												if err
													cb err
													return

												progNoteFiles = result
												# console.log "progNoteFiles", progNoteFiles
												cb()
										(cb) =>
											console.log "About to loop through progNote files, which are: ", progNoteFiles

											# Loop through each progNote file
											Async.eachSeries progNoteFiles, (progNoteFile, cb) ->

												progNoteFilePath = Path.join(progNoteDir, progNoteFile)

												console.log "progNoteFilePath : : ", progNoteFilePath

												# Get list of all files in this progNote folder
												# Fs.readdir progNoteFolderPath, (err, result) ->
												# 	if err
												# 		console.error err
												# 		cb err
												# 		return

												# 	progNoteFileList = result

												# 	# Loop through each file in the given progNote folder
												# 	Async.eachSeries progNoteFileList, (progNoteFile, cb) ->

												# 		progNoteFilePath = Path.join(progNoteFolderPath, progNoteFile)
												# 		console.log "progNoteFilePath", progNoteFilePath

												# 		Fs.readFile progNoteFilePath, (err, result) ->
												# 			if err
												# 				cb err
												# 				return

												# 			# progNoteJSON = JSON.parse adminPwEncryptionKey.decrypt result
												# 			# console.log "progNoteJSON", progNoteJSON
												# 			console.info "JSON RESULT:", JSON.parse result
												# 			console.warn "It's a miracle!!!"
												# 			cb()
												# 	, cb
												cb()

											, cb
									], cb
									
								, cb

						], cb
					, cb
			], cb
	}
])

module.exports = {runMigration, migrate}
