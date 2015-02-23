module.exports = {
	productName: 'KoNote'
	logoSubtitle: 'DSSS'
	logoSubtitleColor: 'hsl(205, 78%, 47%)'
	useTemplate: 'clientLog'
	templates: {
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
