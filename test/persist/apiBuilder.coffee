Assert = require 'assert'
Async = require 'async'
Fs = require 'fs'
Imm = require 'immutable'
Joi = require 'joi'
Mkdirp = require 'mkdirp'
Moment = require 'moment'
Path = require 'path'
Rimraf = require 'rimraf'

{buildApi} = require '../../persist/apiBuilder'
{SymmetricEncryptionKey} = require '../../persist/crypto'
{TimestampFormat} = require '../../persist/utils'

dataDir = Path.join process.cwd(), 'testData'

# Mock session object
s = {
	userName: 'test-user'
	accountType: 'normal'
	globalEncryptionKey: SymmetricEncryptionKey.generate()
	dataDirectory: dataDir
}

describe 'ApiBuilder', ->
	describe '.buildApi', ->
		before (cb) ->
			Rimraf dataDir, cb

		# Set up the user account files before each test
		beforeEach (cb) ->
			Mkdirp dataDir, cb

		afterEach (cb) ->
			Rimraf dataDir, cb

		it 'returns basic API with no collections if no definitions', ->
			api = buildApi(s, [])
			Assert.deepEqual api, {
				eventBus: api.eventBus
				setUpDataDirectory: api.setUpDataDirectory
				ObjectNotFoundError: api.ObjectNotFoundError
			}

		it 'refuses to allow a collection named `setUpDataDirectory`', ->
			Assert.throws ->
				api = buildApi(s, [{
					name: 'setUp'
					collectionName: 'setUpDataDirectory'
					schema: Joi.object()
				}])
			, /setUpDataDirectory/

		it 'refuses to allow name=""', ->
			Assert.throws ->
				api = buildApi(s, [{
					name: ''
					collectionName: 'validCollectionName'
					schema: Joi.object()
				}])
			, /name.*""/

		it 'refuses to allow collectionName=""', ->
			Assert.throws ->
				api = buildApi(s, [{
					name: 'validName'
					collectionName: ''
					schema: Joi.object()
				}])
			, /collection.*""/

		it 'sets up data directory for collections', (cb) ->
			api = buildApi s, [
				{
					name: 'a'
					collectionName: 'a'
					schema: Joi.object()
				}
				{
					name: 'b'
					collectionName: 'b'
					schema: Joi.object()
				}
			]
			api.setUpDataDirectory (err) ->
				if err
					cb err
					return

				Assert Fs.existsSync Path.join(dataDir, 'a')
				Assert Fs.existsSync Path.join(dataDir, 'b')

				cb()

		describe 'immutable data models', ->
			immutablePersonDataModel = {
				name: 'person'
				collectionName: 'people'
				indexes: [
					['name']
					['nested', 'a', 'b']
					['nested', 'a', 'c']
				]
				schema: Joi.object().keys({
					name: Joi.string()
					age: Joi.number()
					nested: Joi.object().keys({
						a: Joi.object().keys({
							b: Joi.string()
							c: Joi.string()
						})
					})
				})
			}
			api = buildApi s, [immutablePersonDataModel]

			beforeEach (cb) ->
				api.setUpDataDirectory cb

			it 'provides a create method', (cb) ->
				api.people.create Imm.Map({
					name: 'John Smith'
					age: 30
				}), (err, result) ->
					if err
						cb err
						return

					now = Moment()

					Assert.strictEqual result.keySeq().size, 6

					Assert.strictEqual typeof result.get('id'), 'string'
					Assert.strictEqual typeof result.get('revisionId'), 'string'
					ts = Moment(result.get('timestamp'), TimestampFormat)
					Assert Math.abs(ts.diff(now)) < 2000
					Assert.strictEqual result.get('author'), 'test-user'

					Assert.strictEqual result.get('name'), 'John Smith'
					Assert.strictEqual result.get('age'), 30

					cb()

			it 'create fails if given an ID', (cb) ->
				api.people.create Imm.Map({
					id: 'badid'
					name: 'John Smith'
					age: 30
				}), (err, result) ->
					Assert err
					Assert not result

					cb()

			it 'create method fails on schema violation', (cb) ->
				api.people.create Imm.Map({
					name: 'John Smith'
					xxx: 30
				}), (err, result) ->
					Assert err
					Assert err instanceof Error
					Assert not result

					cb()

			it 'provides a list method', (cb) ->
				indexTestValue = "a.t^$#&est'/\\:%`~|"

				api.people.create Imm.fromJS({
					name: 'John Smith'
					age: 30
					nested:
						a:
							b: indexTestValue
							c: 'c'
				}), (err, result) ->
					if err
						cb err
						return

					johnSmithId = result.get('id')

					api.people.list (err, results) ->
						if err
							cb err
							return

						expected = [{
							id: johnSmithId
							name: 'John Smith'
							nested:
								a:
									b: indexTestValue
									c: 'c'
							_dirPath: results.getIn [0, '_dirPath']
						}]
						Assert.deepEqual results.toJS(), expected

						cb()

			it 'list rejects too many arguments', (cb) ->
				api.people.list 20, 20, (err, result) ->
					Assert err
					Assert not result

					cb()

			it 'provides a read method', (cb) ->
				api.people.create Imm.Map({
					name: 'John Smith'
					age: 30
				}), (err, result) ->
					if err
						cb err
						return

					johnSmithId = result.get('id')

					api.people.read johnSmithId, (err, obj) ->
						if err
							cb err
							return

						Assert.deepEqual obj.toJS(), result.toJS()

						cb()

			it 'read fails with ObjectNotFoundError for an unknown ID', (cb) ->
				api.people.read 'unknownId', (err, obj) ->
					Assert err
					Assert err instanceof api.ObjectNotFoundError
					Assert not obj

					cb()

			it 'does not provide a createRevision method', ->
				Assert.strictEqual api.people.createRevision, undefined

			it 'does not provide a readRevisions method', ->
				Assert.strictEqual api.people.readRevisions, undefined

			it 'does not provide a readLatestRevisions method', ->
				Assert.strictEqual api.people.readLatestRevisions, undefined

		describe 'mutable data models', ->
			mutablePersonDataModel = {
				name: 'person'
				collectionName: 'people'
				isMutable: true
				indexes: [
					['name']
					['nested', 'a', 'b']
					['nested', 'a', 'c']
				]
				schema: Joi.object().keys({
					name: Joi.string()
					age: Joi.number()
					nested: Joi.object().keys({
						a: Joi.object().keys({
							b: Joi.string()
							c: Joi.string()
						})
					})
				})
			}
			api = buildApi s, [mutablePersonDataModel]

			beforeEach (cb) ->
				api.setUpDataDirectory cb

			it 'provides a create method', (cb) ->
				api.people.create Imm.Map({
					name: 'John Smith'
					age: 30
				}), (err, result) ->
					if err
						cb err
						return

					now = Moment()

					Assert.strictEqual result.keySeq().size, 6

					Assert.strictEqual typeof result.get('id'), 'string'
					Assert.strictEqual typeof result.get('revisionId'), 'string'
					ts = Moment(result.get('timestamp'), TimestampFormat)
					Assert Math.abs(ts.diff(now)) < 2000
					Assert.strictEqual result.get('author'), 'test-user'

					Assert.strictEqual result.get('name'), 'John Smith'
					Assert.strictEqual result.get('age'), 30

					cb()

			it 'create method fails on schema violation', (cb) ->
				api.people.create Imm.Map({
					name: 'John Smith'
					xxx: 30
				}), (err, result) ->
					Assert err
					Assert err instanceof Error
					Assert not result

					cb()

			it 'provides a list method', (cb) ->
				indexTestValue = "a.t^$#&est'/\\:%`~|"

				api.people.create Imm.fromJS({
					name: 'John Smith'
					age: 30
					nested:
						a:
							b: indexTestValue
							c: 'c'
				}), (err, result) ->
					if err
						cb err
						return

					johnSmithId = result.get('id')

					api.people.list (err, results) ->
						if err
							cb err
							return

						expected = [{
							id: johnSmithId
							name: 'John Smith'
							nested:
								a:
									b: indexTestValue
									c: 'c'
							_dirPath: results.getIn [0, '_dirPath']
						}]
						Assert.deepEqual results.toJS(), expected

						cb()

			it 'list reflects changes to indexed properties', (cb) ->
				api.people.create Imm.Map({
					name: 'John Smith'
					age: 30
				}), (err, result) ->
					if err
						cb err
						return

					johnSmithId = result.get('id')

					api.people.createRevision Imm.Map({
						id: johnSmithId
						name: 'John Wells'
						age: 30
					}), (err, result) ->
						if err
							cb err
							return

						api.people.list (err, results) ->
							if err
								cb err
								return

							Assert.strictEqual results.size, 1
							Assert.strictEqual results.getIn([0, 'id']), johnSmithId
							Assert.strictEqual results.getIn([0, 'name']), 'John Wells'

							cb()
			it 'provides a createRevision method', (cb) ->
				api.people.create Imm.Map({
					name: 'John Smith'
					age: 30
				}), (err, result) ->
					if err
						cb err
						return

					johnSmithId = result.get('id')
					firstRevisionId = result.get('revisionId')

					api.people.createRevision Imm.Map({
						id: johnSmithId
						name: 'John Smith'
						age: 31
					}), (err, result) ->
						if err
							cb err
							return

						Assert.strictEqual result.get('id'), johnSmithId
						Assert.notStrictEqual result.get('revisionId'), firstRevisionId
						Assert.strictEqual typeof result.get('revisionId'), 'string'
						Assert.strictEqual result.get('author'), 'test-user'
						Assert.strictEqual typeof result.get('timestamp'), 'string'

						Assert.strictEqual result.get('name'), 'John Smith'
						Assert.strictEqual result.get('age'), 31

						secondRevisionId = result.get('revisionId')
						cb()

			it 'createRevision fails without an ID', (cb) ->
				api.people.createRevision Imm.Map({
					name: 'John Smith'
					age: 32
				}), (err, result) ->
					Assert err
					Assert not result

					cb()

			it 'createRevision fails with ObjectNotFoundError when ID unknown', (cb) ->
				api.people.createRevision Imm.Map({
					id: 'unknownId'
					name: 'John Smith'
					age: 35
				}), (err, result) ->
					Assert err
					Assert err instanceof api.ObjectNotFoundError
					Assert not result

					cb()

			it 'createRevision fails on schema violation', (cb) ->
				api.people.create Imm.Map({
					name: 'John Smith'
					age: 30
				}), (err, result) ->
					if err
						cb err
						return

					johnSmithId = result.get('id')

					api.people.createRevision Imm.Map({
						id: johnSmithId
						name: 'John Smith'
						xxx: 31
					}), (err, result) ->
						Assert err
						Assert err instanceof Error
						Assert not result

						cb()

			it 'provides a readRevisions method', (cb) ->
				api.people.create Imm.Map({
					name: 'John Smith'
					age: 30
				}), (err, result) ->
					if err
						cb err
						return

					johnSmithId = result.get('id')
					firstRevisionId = result.get('revisionId')

					api.people.createRevision Imm.Map({
						id: johnSmithId
						name: 'John Smith'
						age: 31
					}), (err, result) ->
						if err
							cb err
							return

						secondRevisionId = result.get('revisionId')

						api.people.readRevisions johnSmithId, (err, results) ->
							if err
								cb err
								return

							Assert.strictEqual results.size, 2

							result = results.get(0)

							Assert.strictEqual result.get('id'), johnSmithId
							Assert.strictEqual result.get('revisionId'), firstRevisionId
							Assert.strictEqual result.get('author'), 'test-user'
							Assert.strictEqual typeof result.get('timestamp'), 'string'

							Assert.strictEqual result.get('name'), 'John Smith'
							Assert.strictEqual result.get('age'), 30

							result = results.get(1)

							Assert.strictEqual result.get('id'), johnSmithId
							Assert.strictEqual result.get('revisionId'), secondRevisionId
							Assert.strictEqual result.get('author'), 'test-user'
							Assert.strictEqual typeof result.get('timestamp'), 'string'

							Assert.strictEqual result.get('name'), 'John Smith'
							Assert.strictEqual result.get('age'), 31

							cb()

			it 'readRevisions fails with ObjectNotFoundError when ID unknown', (cb) ->
				api.people.readRevisions 'unknownId', (err, result) ->
					Assert err
					Assert err instanceof api.ObjectNotFoundError
					Assert not result

					cb()

			it 'provides a readLatestRevisions method', (cb) ->
				johnSmithId = null
				firstRevisionId = null
				secondRevisionId = null
				Async.series [
					(cb) ->
						api.people.create Imm.Map({
							name: 'John Smith'
							age: 30
						}), (err, result) ->
							if err
								cb err
								return

							johnSmithId = result.get('id')
							firstRevisionId = result.get('revisionId')

							cb()
					(cb) ->
						# Need a delay between revisions.
						# Unfortunately, revisions are ordered by timestamp,
						# which is a bit delicate during automated tests.
						setTimeout cb, 10
					(cb) ->
						api.people.createRevision Imm.Map({
							id: johnSmithId
							name: 'John Smith'
							age: 31
						}), (err, result) ->
							if err
								cb err
								return

							secondRevisionId = result.get('revisionId')

							cb()
					(cb) ->
						api.people.readLatestRevisions johnSmithId, 1, (err, results) ->
							if err
								cb err
								return

							Assert.strictEqual results.size, 1
							result = results.get(0)

							Assert.strictEqual result.get('id'), johnSmithId
							Assert.strictEqual result.get('revisionId'), secondRevisionId
							Assert.strictEqual result.get('author'), 'test-user'
							Assert.strictEqual typeof result.get('timestamp'), 'string'

							Assert.strictEqual result.get('name'), 'John Smith'
							Assert.strictEqual result.get('age'), 31

							cb()
				], cb

			it 'readLatestRevisions fails with ObjectNotFoundError when ID unknown', (cb) ->
				api.people.readLatestRevisions 'unknownId', 1, (err, result) ->
					Assert err
					Assert err instanceof api.ObjectNotFoundError
					Assert not result

					cb()

			it 'does not provide a read method', ->
				Assert.strictEqual api.people.read, undefined

		describe 'nested data models with event listeners', ->
			modelDefs = [
				{
					name: 'immSuper'
					collectionName: 'immSupers'
					isMutable: false
					schema: Joi.object().keys({
						a: Joi.string()
					})
					children: [
						{
							name: 'mutSub'
							collectionName: 'mutSubs'
							isMutable: true
							schema: Joi.object().keys({
								b: Joi.string()
							})
						}
					]
				}
				{
					name: 'mutSuper'
					collectionName: 'mutSupers'
					isMutable: true
					schema: Joi.object().keys({
						c: Joi.string()
					})
					children: [
						{
							name: 'immSub'
							collectionName: 'immSubs'
							isMutable: false
							schema: Joi.object().keys({
								d: Joi.string()
							})
						}
					]
				}
			]
			api = buildApi s, modelDefs

			beforeEach (cb) ->
				api.setUpDataDirectory cb

			it 'immutable object with mutable child types', (cb) ->
				supObjId = null
				subObj1Id = null
				subObj2Id = null

				Async.series [
					(cb) ->
						api.eventBus.once 'create:immSuper', (newObj) ->
							Assert newObj.get('id')
							Assert.strictEqual newObj.get('a'), 'hey'

							supObjId = newObj.get('id')

						api.immSupers.create Imm.Map({a: 'hey'}), (err, result) ->
							if err
								cb err
								return

							Assert.strictEqual result.get('id'), supObjId
							Assert.strictEqual result.get('a'), 'hey'

							cb()
					(cb) ->
						api.eventBus.once 'create:mutSub', (newObj) ->
							Assert newObj.get('id')
							Assert.strictEqual newObj.get('immSuperId'), supObjId
							Assert.strictEqual newObj.get('b'), 'hiya'

							subObj1Id = newObj.get('id')

						api.mutSubs.create Imm.Map({
							immSuperId: supObjId
							b: 'hiya'
						}), (err, result) ->
							if err
								cb err
								return

							Assert.strictEqual result.get('id'), subObj1Id
							Assert.notStrictEqual result.get('id'), supObjId
							Assert.strictEqual result.get('immSuperId'), supObjId
							Assert.strictEqual result.get('b'), 'hiya'

							cb()
					(cb) ->
						api.eventBus.once 'create:mutSub', (newObj) ->
							Assert newObj.get('id')
							Assert.strictEqual newObj.get('immSuperId'), supObjId
							Assert.strictEqual newObj.get('b'), 'yo'

							subObj2Id = newObj.get('id')

						api.mutSubs.create Imm.Map({
							immSuperId: supObjId
							b: 'yo'
						}), (err, result) ->
							if err
								cb err
								return

							Assert.strictEqual result.get('id'), subObj2Id
							Assert.notStrictEqual result.get('id'), supObjId
							Assert.notStrictEqual result.get('id'), subObj1Id
							Assert.strictEqual result.get('immSuperId'), supObjId
							Assert.strictEqual result.get('b'), 'yo'

							cb()
					(cb) ->
						api.immSupers.list (err, results) ->
							if err
								cb err
								return

							Assert.deepEqual results.toJS(), [{
								id: supObjId
								_dirPath: results.getIn [0, '_dirPath']
							}]

							cb()
					(cb) ->
						api.immSupers.read supObjId, (err, result) ->
							if err
								cb err
								return

							Assert.strictEqual result.get('id'), supObjId
							Assert.strictEqual result.get('a'), 'hey'

							cb()
					(cb) ->
						api.mutSubs.list supObjId, (err, results) ->
							if err
								cb err
								return

							Assert.strictEqual results.size, 2

							[result1, result2] = results.toArray()

							# Do we need to swap these?
							if result1.get('id') is subObj2Id
								# Yes, we do.
								[result1, result2] = [result2, result1]

							Assert.deepEqual result1.toJS(), {
								id: subObj1Id
								_dirPath: result1.get('_dirPath')
							}
							Assert.deepEqual result2.toJS(), {
								id: subObj2Id
								_dirPath: result2.get('_dirPath')
							}

							cb()
					(cb) ->
						api.eventBus.once 'createRevision:mutSub', (newRev) ->
							Assert.strictEqual newRev.get('id'), subObj1Id
							Assert.strictEqual newRev.get('immSuperId'), supObjId
							Assert.strictEqual newRev.get('b'), 'xx'

							cb()

						api.mutSubs.createRevision Imm.Map({
							immSuperId: supObjId
							id: subObj1Id
							b: 'xx'
						}), (err, result) ->
							if err
								cb err
								return

							Assert.strictEqual result.get('id'), subObj1Id
							Assert.strictEqual result.get('immSuperId'), supObjId
							Assert.strictEqual result.get('b'), 'xx'

							# See event listener
					(cb) ->
						api.mutSubs.readRevisions supObjId, subObj1Id, (err, revs) ->
							if err
								cb err
								return

							Assert.strictEqual revs.size, 2

							[rev1, rev2] = revs.toArray()

							Assert.strictEqual rev1.get('id'), subObj1Id
							Assert rev1.get('revisionId')
							Assert.strictEqual rev1.get('immSuperId'), supObjId
							Assert.strictEqual rev1.get('b'), 'hiya'

							Assert.strictEqual rev2.get('id'), subObj1Id
							Assert rev2.get('revisionId')
							Assert.strictEqual rev2.get('immSuperId'), supObjId
							Assert.strictEqual rev2.get('b'), 'xx'

							cb()
					(cb) ->
						api.mutSubs.readLatestRevisions supObjId, subObj1Id, 1, (err, revs) ->
							if err
								cb err
								return

							Assert.strictEqual revs.size, 1

							rev1 = revs.get(0)

							Assert.strictEqual rev1.get('id'), subObj1Id
							Assert.strictEqual rev1.get('immSuperId'), supObjId
							Assert.strictEqual rev1.get('b'), 'xx'

							cb()
				], cb

			it 'mutable object with immutable child types', (cb) ->
				supObjId = null
				supObjRevId1 = null
				supObjRevId2 = null
				subObjId = null
				subObjRevId = null

				Async.series [
					(cb) ->
						api.mutSupers.create Imm.Map({c: 'thing1'}), (err, result) ->
							if err
								cb err
								return

							Assert result.get('id')
							Assert result.get('revisionId')
							Assert.strictEqual result.get('c'), 'thing1'

							supObjId = result.get('id')
							supObjRevId1 = result.get('revisionId')
							cb()
					(cb) ->
						api.eventBus.once 'create:immSub', (newObj) ->
							Assert newObj.get('id')
							Assert.strictEqual newObj.get('mutSuperId'), supObjId
							Assert.strictEqual newObj.get('d'), 'thing2'

							subObjId = newObj.get('id')

						api.immSubs.create Imm.Map({
							mutSuperId: supObjId
							d: 'thing2'
						}), (err, result) ->
							if err
								cb err
								return

							Assert.strictEqual result.get('id'), subObjId
							Assert.notStrictEqual result.get('id'), supObjId
							Assert result.get('revisionId')
							Assert.notStrictEqual result.get('revisionId'), supObjRevId1
							Assert.strictEqual result.get('mutSuperId'), supObjId
							Assert not result.has('c')
							Assert.strictEqual result.get('d'), 'thing2'

							subObjRevId = result.get('revisionId')

							cb()
					(cb) ->
						api.eventBus.once 'createRevision:mutSuper', (newRev) ->
							Assert.strictEqual newRev.get('id'), supObjId
							Assert newRev.get('revisionId')
							Assert.strictEqual newRev.get('c'), 'thing3'

							supObjRevId2 = newRev.get('revisionId')

						api.mutSupers.createRevision Imm.Map({
							id: supObjId
							c: 'thing3'
						}), (err, result) ->
							if err
								cb err
								return

							Assert.strictEqual result.get('id'), supObjId
							Assert.strictEqual result.get('revisionId'), supObjRevId2
							Assert.notStrictEqual result.get('revisionId'), supObjRevId1
							Assert.notStrictEqual result.get('revisionId'), subObjRevId
							Assert.strictEqual result.get('c'), 'thing3'
							Assert not result.has('d')

							cb()
					(cb) ->
						api.mutSupers.list (err, results) ->
							if err
								cb err
								return

							Assert.deepEqual results.toJS(), [{
								id: supObjId
								_dirPath: results.getIn [0, '_dirPath']
							}]

							cb()
					(cb) ->
						api.immSubs.read supObjId, subObjId, (err, result) ->
							if err
								cb err
								return

							Assert.strictEqual result.get('id'), subObjId
							Assert.strictEqual result.get('revisionId'), subObjRevId
							Assert.strictEqual result.get('mutSuperId'), supObjId
							Assert not result.has('c')
							Assert.strictEqual result.get('d'), 'thing2'

							cb()
					(cb) ->
						api.immSubs.list supObjId, (err, results) ->
							if err
								cb err
								return

							Assert.deepEqual results.toJS(), [{
								id: subObjId
								_dirPath: results.getIn [0, '_dirPath']
							}]

							cb()
				], cb
