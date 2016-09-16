# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

Async = require 'async'
Base64url = require 'base64url'
Fs = require 'fs'
Imm = require 'immutable'
Path = require 'path'
Request = require 'request'

BatchingFreezableQueue = require '../batchingFreezableQueue'
FileSystemBackend = require './fileSystemBackend'

{
	flattenModelDefs
} = require '../utils'

create = (eventBus, globalEncryptionKey, serverUrl, localDataDirectory, dataModelDefinitions) ->
	# We need to be able to look up a data model definition by collection name
	# efficiently, so we'll put them into a flat Imm.Map structure. Each model
	# def is paired with its context.
	#
	# Example:
	# Imm.Map({
	#   collectionA: Imm.Map({
	#     context: Imm.List([grandparentModelDef, parentModelDef])
	#     modelDef: collectionAModelDef
	#   })
	# })
	collectionInfoByName = flattenModelDefs dataModelDefinitions

	# We'll reuse the file system backend to store data locally.
	# This allows offline access.
	# The built-in encryption of this backend is a bonus.
	# FileSystemBackend will automatically fire the appropriate
	# create createRevision events on the event bus when needed.
	localDataStore = FileSystemBackend.create eventBus, globalEncryptionKey, localDataDirectory

	# Start in offline mode by default
	# Valid modes: 'online', 'sync-pull', 'sync-push', 'offline'
	mode = 'offline'

	# Since offline mode is default, pull loop is inactive by default
	# Valid modes: 'active', 'inactive'
	pullLoopMode = 'inactive'

	# The time index of the most recent event that we've seen on this client.
	# This will be retrieved from the data directory the first time we go online.
	localTimeIndex = null

	# Set up event push queue.
	# This queue is used to submit events to the server in batches of 20,
	# which is more efficient than submitting one event per request.
	# Using a queue also ensures that only one request is submitted to the
	# server at a time.
	# Having more than one request at once will make calculating the right base
	# time index much more difficult.
	pushQueue = BatchingFreezableQueue.create 50, (tasks, markTasksComplete, freeze, next) ->
		events = Imm.List(tasks).map((t) -> t.taskInfo)

		callCallbacks = (args...) ->
			tasks.forEach (t) ->
				process.nextTick ->
					t.callback.apply(null, args)

		Request.post {
			url: serverUrl + '/append-events'
			json: {
				baseTimeIndex: localTimeIndex
				newEvents: events.map (event, eventIndex) ->
					eventType = event.get('type')

					Assert eventType in [
						'create-object',
						'create-object-revision',
						'acquire-lock',
						'release-lock',
						'migration',
					], 'unknown event type: ' + JSON.stringify eventType

					# TODO validate event against Joi schema?

					if event.has('timeIndex')
						# Time index is set by this method.
						# This might indicate that this event has already been sent to
						# the server.
						throw new Error "event object improperly contains a time index"

					eventTimeIndex = eventIndex + localTimeIndex + 1
					event = event.set('timeIndex', eventTimeIndex)

					return {
						type: eventType
						timeIndex: eventTimeIndex
						details: Base64url.encode(
							globalEncryptionKey.encrypt JSON.stringify event.toJS()
						)
					}
				.toArray()
			}
		}, (err, response, body) ->
			# If a network error occurred
			if err
				# TODO handle network error?
				# wrap in IOError?
				markTasksComplete()
				callCallbacks err
				next()
				return

			unless response.statusCode is 200
				if response.statusCode is 409
					# The base time index we provided was wrong.
					# We'll need to wait to receive the new events from the server
					# before trying again.
					freeze()

					# The event pull loop should unfreeze the push queue
					# automatically, but just in case of a race condition...
					setTimeout ->
						pushQueue.unfreeze()
					, 2000
					return

				markTasksComplete()
				console.error JSON.stringify body
				callCallbacks new Error "server returned status code " + response.statusCode
				next()
				return

			# It worked!
			markTasksComplete()
			callCallbacks()
			next()

	createObject = (obj, context, modelDef, cb) ->
		# TODO check mode, add to offline queue if needed, reject if sync

		event = Imm.Map({
			type: 'create-object'
			collectionName: modelDef.collectionName
			object: obj
		})

		# Submit event to push queue
		pushQueue.addTask event, cb

		# TODO invoke callback when event received via pull loop, not right away

	listObjectsInCollection = (contextualIds, context, modelDef, cb) ->
		# Just pass the request through to the local data store
		localDataStore.listObjectsInCollection contextualIds, context, modelDef, cb

	readObject = (contextualIds, id, context, modelDef, cb) ->
		# Just pass the request through to the local data store
		localDataStore.readObject contextualIds, id, context, modelDef, cb

	createObjectRevision = (obj, context, modelDef, cb) ->
		# TODO check mode, reject if offline or sync

		event = Imm.Map({
			type: 'create-object-revision'
			collectionName: modelDef.collectionName
			revision: obj
		})

		# Submit event to push queue
		pushQueue.addTask event, cb

		# TODO invoke callback when event received via pull loop, not right away

	listObjectRevisions = (contextualIds, id, context, modelDef, cb) ->
		# Just pass the request through to the local data store
		localDataStore.listObjectRevisions contextualIds, id, context, modelDef, cb

	readObjectRevision = (contextualIds, id, revisionId, context, modelDef, cb) ->
		# Just pass the request through to the local data store
		localDataStore.readObjectRevision contextualIds, id, revisionId, context, modelDef, cb

	goOnline = (cb) ->
		if mode in ['online', 'sync-pull', 'sync-push']
			cb()
			return

		unless mode is 'offline'
			throw new Error "unknown cloud backend mode: #{JSON.stringify mode}"

		# Change mode to prevent createObject and createObjectRevision from being used during sync.
		# sync-pull will also prevent the pull loop (if it's active) from
		# interfering with the catch up step of synchronizing.
		mode = 'sync-pull'

		offlineQueueFilePaths = null
		offlineQueueFiles = null

		Async.series [
			(cb) ->
				# If time index already loaded from local file system
				if localTimeIndex isnt null
					# Carry on
					cb()
					return

				# Figure out how much catching up we have to do
				Fs.readdir Path.join(localDataDirectory, '_timeIndex'), (err, fileNames) ->
					if err
						cb err
						return

					if fileNames.length < 1
						throw new Error "time index file is missing"

					if fileNames.length > 1
						throw new Error "too many files inside _timeIndex"

					localTimeIndex = parseInt(fileNames[0], 10)
					cb()
			(cb) ->
				# Repeatedly pull events from server until we're caught up
				initialLocalTimeIndex = localTimeIndex
				remoteTimeIndex = Infinity
				Async.whilst(
					->
						localTimeIndex < remoteTimeIndex
					, (cb) ->
						newEvents = null

						Async.series [
							(cb) ->
								Request.post {
									url: serverUrl + '/read-events'
									json: {
										sinceTimeIndex: localTimeIndex
									}
								}, (err, response, body) ->
									if err
										# TODO wrap with IOError?
										cb err
										return

									if response.statusCode isnt 200
										cb new Error "server returned status code " + response.statusCode
										return

									remoteTimeIndex = body.currentTimeIndex
									newEvents = Imm.fromJS body.events
									cb()
							(cb) ->
								Async.eachSeries newEvents.toArray(), processEventFromServer, cb
						], (err) ->
							if err
								cb err
								return

							eventBus.trigger(
								'sync:pullProgress', initialLocalTimeIndex, localTimeIndex, remoteTimeIndex
							)
							cb()
					, cb
				)
			(cb) ->
				# Now that we're caught up, we can start the pull loop in the background
				mode = 'sync-push' # signal that pull loop is now permitted to run
				startPullLoop()

				# Read list of all events that were created locally while offline
				offlineQueueDir = Path.join(localDataDirectory, '_offlineQueue')
				Fs.readdir offlineQueueDir, (err, fileNames) ->
					if err
						cb err
						return

					offlineQueueFilePaths = Imm.List(fileNames).map (fileName) ->
						return Path.join(offlineQueueDir, fileName)
					cb()
			(cb) ->
				# For each event in offline queue
				Async.eachOfSeries offlineQueueFilePaths.toArray(), (path, fileIndex, cb) ->
					event = null

					Async.series [
						(cb) ->
							# Read event from file
							Fs.readFile path, (err, result) ->
								if err
									cb err
									return

								event = Imm.fromJS JSON.parse result
								cb()
						(cb) ->
							# Submit event to server
							# TODO in push worker: assert no object with ID exists in localDataStore
							# to prevent double submits (?)
							pushQueue.addTask event, cb
						(cb) ->
							# Delete from local queue, now that the server has it
							Fs.unlink offlineQueueFilePaths.get(fileIndex), cb
						(cb) ->
							eventBus.trigger 'sync:pushProgress', fileIndex + 1, offlineQueueFilePaths.size
							cb()
					], cb
				, cb
		], (err) ->
			if err
				# Revert to offline so that the user can try again
				# TODO will this leave pull loop in an inconsistent state?
				mode = 'offline'

				cb err
				return

			# We're now online!
			mode = 'online'
			eventBus.trigger 'sync:complete'
			cb()

	goOffline = (cb) ->
		if mode is 'offline'
			cb()
			return

		if mode in ['sync-pull', 'sync-push']
			cb new Error "cannot go offline until synchronizing has completed"
			return

		unless mode is 'online'
			throw new Error "unknown cloud backend mode: #{JSON.stringify mode}"

		# Change mode to offline.
		# The pull loop will notice the change and become inactive.
		mode = 'offline'

		# Leave the push worker running. It will finish what it can, if it can.
		# Once the push queue is empty, it will lie dormant.

		# TODO wait for push queue to clear?
		cb()

	startPullLoop = ->
		if pullLoopMode is 'active'
			# Pull loop is already running
			return

		unless pullLoopMode is 'inactive'
			throw new Error "unknown pull loop mode " + JSON.stringify pullLoopMode

		# Set mode to active
		pullLoopMode = 'active'

		Async.whilst(
			->
				true
			, (cb) ->
				newEvents = null

				Async.series [
					(cb) ->
						Request.post {
							url: serverUrl + '/read-events'
							json: {
								sinceTimeIndex: localTimeIndex
							}
						}, (err, response, body) ->
							if mode in ['offline', 'sync-pull']
								# Ignore the actual response (mainly because it could be an error).

								# Deactivate the pull loop
								pullLoopMode = 'inactive'

								# No cb().
								# This will end the loop.
								return

							unless mode in ['online', 'sync-push']
								throw new Error "unknown mode " + JSON.stringify mode

							if err
								# TODO handle error and retry wth exponential back off?
								cb err
								return

							if response.statusCode isnt 200
								cb new Error "server returned status code " + response.statusCode
								return

							newEvents = Imm.fromJS body.events
							cb()
					(cb) ->
						Async.eachSeries newEvents.toArray(), processEventFromServer, cb
					(cb) ->
						# If we got any new events this time
						if newEvents.size > 0
							# The push queue might be frozen,
							# so nudge it to try again now that we have these events
							pushQueue.unfreeze()

						# TODO remove once long polling implemented
						setTimeout cb, 5000
				], cb
			, (err) ->
				if err
					throw err
					return

				# This should never happen because of the whilst true loop
				throw new Error "unreachable"
		)

	processEventFromServer = (event, cb) ->
		if localTimeIndex is null
			throw new Error "cannot process event from server before loading local time index"

		# Decrypt event details
		eventDetails = Imm.fromJS JSON.parse(
			globalEncryptionKey.decrypt Base64url.toBuffer event.get('details')
		)

		# Verify plaintext properties against encrypted details
		if event.get('type') isnt eventDetails.get('type')
			# Event type has been tampered with
			cb new Error "verification error: type in event details"
			return
		if event.get('timeIndex') isnt eventDetails.get('timeIndex')
			# Time index has been tampered with
			cb new Error "verification error: time index in event details"
			return

		# Check that this event comes after the most recent event we've received so far
		timeIndex = eventDetails.get('timeIndex')
		if timeIndex isnt localTimeIndex + 1
			cb new Error "received event with time index #{JSON.stringify timeIndex} from server," +
				" but expected time index #{localTimeIndex + 1}"
			return

		Async.series [
			(cb) ->
				# Respond based on event's type
				eventType = eventDetails.get('type')
				switch eventType
					when 'create-object'
						obj = eventDetails.get('object')

						collectionInfo = collectionInfoByName.get(eventDetails.get('collectionName'))
						context = collectionInfo.get('context')
						modelDef = collectionInfo.get('modelDef')

						localDataStore.createObject obj, context, modelDef, cb
					when 'create-object-revision'
						rev = eventDetails.get('revision')

						collectionInfo = collectionInfoByName.get(eventDetails.get('collectionName'))
						context = collectionInfo.get('context')
						modelDef = collectionInfo.get('modelDef')

						localDataStore.createObjectRevision rev, context, modelDef, cb
					# TODO acquire-lock, release-lock, migration
					else
						throw new Error "received unknown event type from server " + JSON.stringify eventType
			(cb) ->
				# Update time index to reflect the new event we've processed
				if timeIndex isnt localTimeIndex + 1
					# This shouldn't be possible because of the same check above.
					# localTimeIndex was modified concurrently with this method,
					# which shouldn't be possible.
					cb new Error "detected race condition"
					return

				oldPath = Path.join(localDataDirectory, '_timeIndex', localTimeIndex + '')
				localTimeIndex += 1
				newPath = Path.join(localDataDirectory, '_timeIndex', localTimeIndex + '')

				# Update time index on file system
				Fs.rename oldPath, newPath, cb
		], cb

	return {
		goOnline
		goOffline
		createObject
		listObjectsInCollection
		readObject
		createObjectRevision
		listObjectRevisions
		readObjectRevision
	}

module.exports = {create}
