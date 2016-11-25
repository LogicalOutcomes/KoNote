# ////////////////////// Migration Series //////////////////////

module.exports = {
	run: (dataDir, userName, password, lastMigrationStep, cb) ->
		console.log "No migrations to run for v1.12.1"
		cb()
}