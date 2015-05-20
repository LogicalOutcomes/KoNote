module.exports = {
	productName: 'KoNote'
	logoSubtitle: 'DSSS'
	logoSubtitleColor: 'hsl(205, 78%, 47%)'

	# TODO: Set these up around the app
	clientFileRecordNumber: {
		isEnabled: true
		isRequired: true
		label: "CR #"
	}

	#useTemplate: 'initialAssessment'
	useTemplate: 'clientLog'
	templates: {
		initialAssessment: {
			id: 'initAssessGC'
			name: 'Client Log - Initial Assessment'
			sections: [
				{
					id: 'peerInt'
					type: 'basic'
					name: 'Peer Interactions'
					metricIds: []
				}
				{
					id: 'staffInt'
					type: 'basic'
					name: 'Staff Interactions'
					metricIds: []
				}
				{
					id: 'partProgramming'
					type: 'basic'
					name: 'Participation in Programming'
					metricIds: []
				}
				{
					id: 'partAcademics'
					type: 'basic'
					name: 'Participation in Academics'
					metricIds: []
				}
				{
					id: 'descGenPres'
					type: 'basic'
					name: 'Description of General Presentation'
					metricIds: []
				}
				{
					id: 'descCoping'
					type: 'basic'
					name: 'Description of Coping Skills Exhibited'
					metricIds: []
				}
				{
					id: 'staffFamily'
					type: 'basic'
					name: 'Staff Contact with Family'
					metricIds: []
				}
				{
					id: 'additional'
					type: 'basic'
					name: 'Additional Comments Related to Domains / General Comments (including incidents, etc)'
					metricIds: []
				}
				{
					id: 'checkin'
					type: 'basic'
					name: 'Feedback from Client Check-In'
					metricIds: []
				}
				{
					id: 'sr'
					type: 'basic'
					name: 'School Readiness'
					metricIds: [
						'sr1'
						'sr2'
						'sr3'
						'sr4'
					]
				}
				{
					id: 'ss'
					type: 'basic'
					name: 'Social Skills'
					metricIds: [
						'ss1'
						'ss2'
						'ss3'
						'ss4'
					]
				}
				{
					id: 'life'
					type: 'basic'
					name: 'Life Skills'
					metricIds: [
						'life1'
						'life2'
					]
				}
				{
					id: 'leisure'
					type: 'basic'
					name: 'Leisure Skills'
					metricIds: [
						'leisure1'
						'leisure2'
					]
				}
			]
		}
		clientLog: {
			id: 'clientLogGC'
			name: 'Client Log'
			sections: [
				{
					id: 'goals'
					type: 'plan'
					name: 'Client Goals'
				}
				{
					id: 'peerInt'
					type: 'basic'
					name: 'Peer Interactions'
					metricIds: []
				}
				{
					id: 'staffInt'
					type: 'basic'
					name: 'Staff Interactions'
					metricIds: []
				}
				{
					id: 'partProgramming'
					type: 'basic'
					name: 'Participation in Programming'
					metricIds: []
				}
				{
					id: 'partAcademics'
					type: 'basic'
					name: 'Participation in Academics'
					metricIds: []
				}
				{
					id: 'descGenPres'
					type: 'basic'
					name: 'Description of General Presentation'
					metricIds: []
				}
				{
					id: 'descCoping'
					type: 'basic'
					name: 'Description of Coping Skills Exhibited'
					metricIds: []
				}
				{
					id: 'staffFamily'
					type: 'basic'
					name: 'Staff Contact with Family'
					metricIds: []
				}
				{
					id: 'additional'
					type: 'basic'
					name: 'Additional Comments'
					metricIds: []
				}
				{
					id: 'checkin'
					type: 'basic'
					name: 'Feedback from Client Check-In'
					metricIds: []
				}
			]
		}
		soap: {
			id: 'fake-template-lolololol'
			name: 'Fake Template'
			sections: [
				{
					id: 'section1'
					type: 'basic'
					name: 'Subjective'
					metricIds: ['score']
				}
				{
					id: 'section2'
					type: 'basic'
					name: 'Objective'
					metricIds: []
				}
				{
					id: 'section3'
					type: 'basic'
					name: 'Assessment'
					metricIds: []
				}
				{
					id: 'section4'
					type: 'plan'
					name: 'Plan'
				}
			]
		}
	}
}
