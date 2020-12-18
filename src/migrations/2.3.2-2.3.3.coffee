# ////////////////////// Migration Series //////////////////////

module.exports = {
	run: (dataDir, userName, password, lastMigrationStep, cb) ->
		console.log "No migrations to run for v2.3.3"
		cb()
}
