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
Base64url = require 'base64url'
Fs = require 'fs'
Imm = require 'immutable'
Path = require 'path'
Ncp = require 'ncp'

# Use this at the command line
runMigration = (dataDir, fromVersion, toVersion, userName, password) ->
	stagedDataDir = "./data_migration_#{fromVersion}-#{toVersion}"
	backupDataDir = "./data_migration_#{fromVersion}--backup"

	Async.series [
		(cb) -> # Copy the dataDir to a staging dir
			Ncp dataDir, stagedDataDir, (err) ->
				if err
					console.error "Database staging error!"
					cb err
					return

				console.info "1. Database staging successful."
				cb()

		(cb) -> # Run migration on staged database dir
			migrate stagedDataDir, fromVersion, toVersion, userName, password, (err) ->
				if err
					console.error "Database migration error!"
					cb err
					return

				console.info "2. Data migration successful."
				cb()

		(cb) -> # Move (rename) live database to app directory			
			Fs.rename dataDir, backupDataDir, (err) ->
				if err
					console.error "Database backup error!"
					cb err
					return

				console.info "3. Database backup successful."
				setTimeout(cb, 5000)

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

				console.info "4. Database commit to destination successful."
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
			return

		console.info "------ Migration Complete! ------"



migrate = (dataDir, fromVersion, toVersion, userName, password, cb) ->
	# Eventually, this could be expanded to support migrating across many
	# versions (e.g. v1 -> v5).

	# TODO: Grab full list of migrations, handle multi-step migrations

	console.log "Running migration step #{fromVersion} -> #{toVersion}..."

	try
		migrationStep = require("./#{fromVersion}-#{toVersion}")
	catch err
		cb err
		return

	migrationStep.run dataDir, userName, password, (err) ->
		if err
			cb new Error "Could not run migration #{fromVersion}-#{toVersion}"
			return

		console.log "Done migration step #{fromVersion} -> #{toVersion}."
		cb()

module.exports = {runMigration, migrate}
