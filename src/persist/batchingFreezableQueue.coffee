# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

_ = require 'underscore'

# maxBatchSize: maximum number of tasks to process at a time
# processBatch: a function for processing a batch. The function will be
# provided four arguments:
#  - tasks: an array of task objects. Each task object contains two fields,
#    taskInfo and callback, both of which are as provided to the addTask method.
#  - markTasksComplete: call this function to indicate that the tasks in this
#    batch can be removed from the queue and should not be included in the next
#    batch.
#  - freeze: call this function to indicate that this batch is done, and that
#    no new batches should be started until unfreeze() is called.
#  - next: call this function to indicate that this batch is done, and that the
#    next batch should be processed.
#
# (number, function) -> BatchingFreezableQueue
create = (maxBatchSize, processBatch) ->
	mode = 'idle'
	queue = []

	startProcessing = ->
		if mode is 'processing'
			# Already started processing
			return

		if mode is 'frozen'
			# Can't start processing until unfrozen
			return

		unless mode is 'idle'
			throw new Error "unknown queue mode " + JSON.stringify mode

		# If there's nothing to process
		if queue.length is 0
			return

		# OK, we're idle, so it's safe to start processing
		mode = 'processing'

		# Figure out how many tasks will be in this batch
		batchSize = Math.min(queue.length, maxBatchSize)

		doneBatch = false

		processBatch(
			queue.slice(0, batchSize),
			_.once -> # Mark as complete
				if doneBatch
					throw new Error "cannot mark batch as complete: batch has already finished"

				# Remove tasks from queue to prevent them from being re-processed
				queue = queue.slice(batchSize)
			-> # Freeze
				if doneBatch
					throw new Error "invalid state: batch processing callback called twice"

				doneBatch = true

				# Go to frozen mode to prevent further processing.
				# Don't start the next batch.
				mode = 'frozen'
			-> # Next
				if doneBatch
					throw new Error "invalid state: batch processing callback called twice"

				doneBatch = true

				# Switch to idle, then start the next batch
				mode = 'idle'
				startProcessing()
		)

	# Wait 50ms before starting processing in order to allow more tasks to accumulate.
	# This will lead to tasks being batched more efficiently.
	startProcessing = _.debounce startProcessing, 50

	return {
		# Add the specified task to the queue to be processed eventually.
		# The callback cb will not be called until the task is processed.
		addTask: (taskInfo, cb) ->
			queue.push({
				taskInfo
				callback: cb
			})
			startProcessing()
		unfreeze: ->
			if mode is 'frozen'
				mode = 'idle'
				startProcessing()
	}

module.exports = {create}
