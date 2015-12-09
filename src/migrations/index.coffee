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

# Use this at the command line
runMigration = (dataDir, fromVersion, toVersion, userName, password) ->
	migrate dataDir, fromVersion, toVersion, userName, password, (err) ->
		if err
			console.error "Migration error."

			# Close any currently open logging groups to make sure the error is seen
			# Yeah, this sucks.
			for i in [0...1000]
				console.groupEnd()

			console.error "Migration failed:"
			console.error err
			console.error err.stack

			if err.cause
				console.error "Caused by:"
				console.error err.cause.stack

			return

		console.log "Migration complete."

migrate = (dataDir, fromVersion, toVersion, userName, password, cb) ->
	# Eventually, this could be expanded to support migrating across many
	# versions (e.g. v1 -> v5).

	# TODO: Grab full list of migrations, handle multi-step migrations

	console.group "Run migration step #{fromVersion} -> #{toVersion}"

	try
		migrationStep = require("./#{fromVersion}-#{toVersion}.coffee")
	catch err
		cb err
		return

	migrationStep.run dataDir, userName, password, (err) ->
		if err
			wrappedErr = new Error "Could not run migration #{fromVersion}-#{toVersion}"
			wrappedErr.cause = err
			cb wrappedErr
			return

		console.groupEnd()
		cb()

module.exports = {runMigration, migrate}
