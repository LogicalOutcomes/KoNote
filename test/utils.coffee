Assert = require 'assert'

{CustomError} = require '../src/utils'

class A extends CustomError
class B extends A

class C extends CustomError
	constructor: (msg, arg2) ->
		super msg
		@arg2 = arg2

describe "CustomError", ->
	it "subclasses should have proper instanceof", ->
		Assert new A() instanceof A
		Assert new A() instanceof Error
		Assert new B() instanceof B
		Assert new B() instanceof A
		Assert new B() instanceof Error
		Assert new A() not instanceof B
		Assert new Error() not instanceof A
		Assert new Error() not instanceof B
	it "subclasses should have err.name set", ->
		Assert new A().name is 'A'
		Assert new B().name is 'B'
	it "subclasses should have err.message set if provided", ->
		Assert new A('abc').message is 'abc'
		Assert new B('abc').message is 'abc'
	it "subclasses should have err.stack set", ->
		Assert new A('abc').stack
		Assert new B('abc').stack
	it "subclasses should have err.stack that contains the error's name and message", ->
		Assert new A('abc').stack.startsWith 'A: abc'
		Assert new B('abc').stack.startsWith 'B: abc'
	it "subclasses should be given a proper toString implementation", ->
		Assert new A('abc').toString() is 'A: abc'
		Assert new B('abc').toString() is 'B: abc'
	it "subclasses should be able to accept custom constructor args", ->
		Assert new C('abc', 342).name is 'C'
		Assert new C('abc', 342).message is 'abc'
		Assert new C('abc', 342).stack.startsWith 'C: abc'
		Assert new C('abc', 342).arg2 is 342
