# Print preview page receives data from the printButton's data,
# and matches printing components with the type(s) of data received

Imm = require 'immutable'

load = (win, {dataSet}) ->
	$ = win.jQuery
	React = win.React
	R = React.DOM

	{timeoutListeners} = require('./timeoutDialog').load(win)

	do ->
		printDataSet = Imm.fromJS JSON.parse(dataSet)

		init = ->
			render()
			registerListeners()

		process.nextTick init

		render = ->
			React.render new PrintPreview({
				printDataSet
			}), $('#container')[0]

		registerListeners = ->
			timeoutListeners()

	PrintPreview = React.createFactory React.createClass
		componentHasMounted: ->
			win.print()

		render: ->
			return R.div({className: 'printPreview'},

				(@props.printDataSet.map (printObj) =>
					data = printObj.get('data')

					switch printObj.get('format')
						when 'progNote'
							switch data.get('type')								
								when 'basic'
									BasicProgNoteView({
										data
										key: data.get('id')
									})
								when 'full'
									FullProgNoteView({
										data
										key: data.get('id')
									})
								else
									throw new Error "Unknown progNote type: #{data.get('type')}"

						else
							throw new Error "Unknown data type: #{setType}"
				)
				
			)

	# ProgNote View Components

	BasicProgNoteView = React.createFactory React.createClass
		render: ->
			console.log "Basic Note"
			return R.div({}, 
				
			)

	FullProgNoteView = React.createFactory React.createClass
		render: ->
			console.log "Full Note"
			return R.div({}, 
				
			)

module.exports = {load}