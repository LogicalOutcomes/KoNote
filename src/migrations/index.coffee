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
Moment = require 'moment'

# Utilities
copyRecursiveSync = (src, dest) ->
	# TODO: Make async, or try/catch err
	exists = Fs.existsSync(src)
	stats = exists and Fs.statSync(src)
	isDirectory = exists and stats.isDirectory()
	if exists and isDirectory
		Fs.mkdirSync dest
		Fs.readdirSync(src).forEach (childItemName) ->
			copyRecursiveSync Path.join(src, childItemName), Path.join(dest, childItemName)
			return
	else
		Fs.linkSync src, dest
	return

writeDataVersion = (dataDir, toVersion, cb) ->
	versionPath = Path.join dataDir, 'version.json'
	metadata = null

	Async.series [
		(cb) ->
			Fs.readFile versionPath, (err, result) ->
				if err
					cb err
					return

				metadata = JSON.parse result
				metadata.dataVersion = toVersion
				cb()
		(cb) ->
			Fs.writeFile versionPath, JSON.stringify(metadata), cb

	], cb

# This loops through migrations until currentVersion = destinationVersion
runMigration = (dataDir, currentVersion, destinationVersion, userName, password, cb) ->
	migrationVersionSets = null

	# This expression is used to filter non-migration files from the migrations directory
	migrationRegex = /([0-9\-.]+\.coffee)/

	Async.series [
		(cb) =>
			# fetch list of migration files
			Fs.readdir "./src/migrations", (err, result) ->
				if err
					cb err
					return

				migrationVersionSets = Imm.fromJS(result)
				.filter (m) -> migrationRegex.exec(m)
				.map (m) ->
					# Parsing migration files, splitting, creating obj
					[fromVersion, toVersion] = m.replace(".coffee", "").split("-")
					return Imm.Map {fromVersion, toVersion}

				cb()

		(cb) =>
			Async.until (-> currentVersion is destinationVersion), (cb) ->
		 		# find a migration to run
				{fromVersion, toVersion} = migrationVersionSets
				.find (m) => m.get('fromVersion') is currentVersion
				.toObject()

				migrate dataDir, fromVersion, toVersion, userName, password, (err) ->
					if err
						cb err
						return
					currentVersion = toVersion
					cb()
					return

			, cb
	], cb

# This sets up the staging directory, can use this at the command line to migrate manually
atomicMigration = (dataDir, fromVersion, toVersion, userName, password, cb=(->)) ->
	randomId = new Date().valueOf()
	stagedDataDir = "./data_migration_#{fromVersion}-#{toVersion}-#{randomId}"
	backupDataDir = "./data_migration_#{fromVersion}--backup-#{Moment().format('YYYY-MM-DD-(h-ssa)')}-#{randomId}"

	Async.series [
		(cb) ->

			# Verify that all versions are valid
			dataDirMetadataPath = Path.join dataDir, 'version.json'

			Fs.readFile dataDirMetadataPath, (err, result) ->
				if err
					console.error "Unable to read version metadata!"
					cb err
					return

				dataDirMetadata = JSON.parse result

				# Ensure fromVersions match
				if dataDirMetadata.dataVersion isnt fromVersion
					cb new Error """
						Version Mismatch! Data directory is currently
						v#{dataDirMetadata.dataVersion}, but trying to install from #{fromVersion}."
					"""
					return

				# Ensure srcVersion (package.json) matches toVersion
				# In other words, the files are ready for the new DB version
				# This is OK in 'development' mode, for interim partial migrations

				# ToDo, check lastMigrationStep logic when iterating over multiple migrations

				# if nw.App.manifest.version isnt toVersion
				# 	if process.env.NODE_ENV isnt 'development'
				# 		console.error """
				# 			Your current src/package files are v#{nw.App.manifest.version},
				# 			which doesn't match the destination data version v#{toVersion}.
				# 		"""
				# 		cb err
				# 		return
				# 	else
				# 		console.warn """
				# 			Developer Mode! The last migration step run was
				# 			Step ##{dataDirMetadata.lastMigrationStep}, so we'll
				# 			start from Step ##{dataDirMetadata.lastMigrationStep + 1}
				# 			if exists.
				# 		"""
				# 		lastMigrationStep = dataDirMetadata.lastMigrationStep

				# All tests passed, continue with data migration
				console.info "1. Version validity check successful."
				cb()


		(cb) -> # Copy the dataDir to a staging dir
			console.log "Copying database to staging folder...."
			copyRecursiveSync dataDir, stagedDataDir
			cb()

		(cb) -> # Run migration on staged database dir
			runMigration stagedDataDir, fromVersion, toVersion, userName, password, (err) ->
				if err
					console.error "Database migration error!"
					cb err
					return

				console.info "3. Data migration successful."
				cb()

		(cb) -> # Backup (move) current database
			Fs.rename dataDir, backupDataDir, (err) ->
				if err
					console.error "Database backup error!"
					cb err
					return

				console.info "4. Database backup successful."
				cb()

		(cb) -> # Move staged (migrated) database to destination
			Fs.rename stagedDataDir, dataDir, (err) ->
				if err
					console.error "Database commit to destination error!"

					# Fail-safe: Since it wasn't successful, restore the original database dir
					Fs.rename backupDataDir, dataDir, (err) ->
						if err
							console.error "Unable to restore original dataDir."
							cb err
							return

						console.info "Successfully restored original dataDir"

					cb err
					return

				console.info "5. Database commit to destination successful."
				cb()

	], (err) ->
		if err
			# Close any currently open logging groups to make sure the error is seen
			# Yeah, this sucks.
			for i in [0...1000]
				console.groupEnd()

			console.error "Migration failed:"
			console.error err
			console.error err.stack
			cb err
			return

		console.info "------ Migration Complete! ------"
		cb()

# This runs a single migration
migrate = (dataDir, fromVersion, toVersion, userName, password, cb) ->
	# lastMigrationStep is no longer relevant, so setting to null
	# ToDo: remove lastMigrationStep(?)
	lastMigrationStep = null

	# ToDo: handle case where migration file is not found
	try
		migration = require("./#{fromVersion}-#{toVersion}")
	catch err
		cb err
		return

	Async.series [
		(cb) =>
			migration.run dataDir, userName, password, lastMigrationStep, cb

		(cb) =>
			writeDataVersion dataDir, toVersion, (err) ->
				if err
					cb err
					return

				console.log "Updated version number in data file to v#{toVersion}"
				cb()

	], (err) =>
		if err
			console.error "Could not run migration #{fromVersion}-#{toVersion}"
			cb err
			return
		cb()
		return

module.exports = {atomicMigration, runMigration, migrate}
