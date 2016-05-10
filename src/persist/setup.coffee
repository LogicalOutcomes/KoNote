# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

Async = require 'async'
Mkdirp = require 'mkdirp'
Path = require 'path'
Fs = require 'fs'

Config = require '../config'
{dataModelDefinitions} = require './dataModels'

createVersionMetadataFile = (dataDir, cb) ->
	versionPath = Path.join(dataDir, 'version.json')
	versionData = {
		dataVersion: Config.version
		lastMigrationStep: 0
	}

	Fs.writeFile versionPath, JSON.stringify(versionData), cb

buildDataDirectory = (dataDir, customDataModelDefinitions, cb) ->
	# Switch cb for customDataModelDefinitions if not provided
	if typeof customDataModelDefinitions is 'function'
		cb = customDataModelDefinitions
	else
		dataModelDefinitions = customDataModelDefinitions

	# Set up top-level directories
	Async.series [
		(cb) ->
			Async.each dataModelDefinitions, (modelDef, cb) ->
				Mkdirp Path.join(dataDir, modelDef.collectionName), cb
			, cb
		(cb) ->
			Mkdirp Path.join(dataDir, '_tmp'), cb
		(cb) ->
			Mkdirp Path.join(dataDir, '_users'), cb
		(cb) ->
			Mkdirp Path.join(dataDir, '_locks'), cb
		(cb) ->
			createVersionMetadataFile dataDir, cb
	], cb

module.exports = {buildDataDirectory}