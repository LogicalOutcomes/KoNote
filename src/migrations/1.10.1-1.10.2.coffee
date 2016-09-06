# ////////////////////// Migration Series //////////////////////

module.exports = {
	run: (dataDir, userName, password, lastMigrationStep, cb) ->
		console.log "No migrations to run for v1.10.2"
		cb()
}