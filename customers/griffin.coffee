# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

module.exports = {
	productName: 'KoNote'
	customerLogoLg: 'customer-logo-lg_GRIFFIN.png'
	customerLogoSm: 'customer-logo-sm_GRIFFIN.png'
	logoSubtitle: 'DSSS'
	logoSubtitleColor: 'hsl(205, 78%, 47%)'

	clientFileRecordId: {
		isEnabled: true
		label: "CR#"
	}

	# Set total timeout in (minutes),
	# and how many mins before timeout to show warning
	timeout: {
		duration: 25
		warnings: {
			initial: 10
			final: 1
		}
	}

	# Set ping time for client file in (minutes)
	clientFilePing: {
		acquireLock: 0.5
	}

	# Set terminology to be used around the app, lowercase only
	# * Only modify the values in double-quotes
	# * Terms are auto pluralized & capitalized in term.coffee
	terminology: {
		'user': "user"
		'account': "account"
		'user account': "user account"

		'client': "client"
		'file': "file"
		'client file': "client file"

		'section': "section"
		'plan': "plan"
		'target': "goal"
		'plan target': "plan goal"

		'progress note': "progress note"
		'quick note': "quick note"

		'metric': "indicator"
		'event': "event"

		'analysis': "analysis"
		'analyze': "analyze"
	}		

	# useTemplate: 'initialAssessment'
	useTemplate: 'clientLog'

}
