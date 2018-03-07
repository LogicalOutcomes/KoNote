// Monkey patch Bootbox to prevent XSS vulnerabilities.
// Instead of accepting raw HTML strings, this patches Bootbox to accept React
// element trees, which makes it much harder to have an XSS vulnerability.

(function () {
	const _ = require('underscore');

	const reactTitleContainerHtml = '<div class="reactTitleContainer"></div>';
	const reactMessageContainerHtml = '<div class="reactMessageContainer"></div>';
	const getReactButtonLabelContainerHtml = (buttonLabelIndex) => {
		return '<span class="reactButtonLabelContainer-' + _.escape(buttonLabelIndex) + '"></span>';
	};

	let rawBootbox = window.bootbox;
	window.bootbox = {
		alert(messageOrOptions, callback) {
			// If first arg is a message
			if (typeof messageOrOptions === 'string'
				|| Array.isArray(messageOrOptions)
				|| React.isValidElement(messageOrOptions)
				|| arguments.length === 2
			) {
				let dialog = rawBootbox.alert(reactMessageContainerHtml, callback);
				dialog.init(() => {
					if (messageOrOptions) {
						ReactDOM.render(
							React.DOM.div({}, messageOrOptions),
							dialog.find('.reactMessageContainer')[0]
						);
					}
				});
				return dialog;
			} else {
				// Assume first arg is options

				let init = cleanUpOptions(messageOrOptions);
				let dialog = rawBootbox.alert(messageOrOptions);
				dialog.init(() => init(dialog));
				return dialog;
			}
		},
		confirm(messageOrOptions, callback) {
			if (arguments.length === 2) {
				let dialog = rawBootbox.confirm(reactMessageContainerHtml, callback);
				dialog.init(() => {
					if (messageOrOptions) {
						ReactDOM.render(
							React.DOM.div({}, messageOrOptions),
							dialog.find('.reactMessageContainer')[0]
						);
					}
				});
				return dialog;
			} else {
				// Assume first (and only) arg is options

				let init = cleanUpOptions(messageOrOptions);
				let dialog = rawBootbox.confirm(messageOrOptions);
				dialog.init(() => init(dialog));
				return dialog;
			}
		},
		prompt(titleOrOptions, callback) {
			if (arguments.length === 2) {
				let dialog = rawBootbox.prompt(reactTitleContainerHtml, callback);
				dialog.init(() => {
					if (titleOrOptions) {
						ReactDOM.render(
							React.DOM.div({}, titleOrOptions),
							dialog.find('.reactTitleContainer')[0]
						);
					}
				});
				return dialog;
			} else {
				// Assume first (and only) arg is options

				if (titleOrOptions.inputType === 'select'
					|| titleOrOptions.inputType === 'checkbox'
				) {
					// These two input types need special handling in order to
					// prevent XSS vulnerabilities. See the Bootbox.js source
					// code.
					throw new Error("not yet implemented");
				}

				if (titleOrOptions.message) {
					throw new Error("custom message not allowed for Bootbox.prompt");
				}

				let init = cleanUpOptions(titleOrOptions);
				let dialog = rawBootbox.prompt(titleOrOptions);
				dialog.init(() => init(dialog));
				return dialog;
			}
		},
		dialog(options) {
			let init = cleanUpOptions(options);
			let dialog = rawBootbox.dialog(options);
			dialog.init(() => init(dialog));
			return dialog;
		},
		hideAll() {
			rawBootbox.hideAll();
		},
	};

	// Mutates the provided options object, replacing HTML strings with
	// placeholders. Run the returned function after the Bootbox dialog has
	// init'd.
	function cleanUpOptions(options) {
		let titleElem = null;
		let messageElem = null;
		let buttonLabelElems = [];

		if (options.title) {
			titleElem = options.title;
			options.title = reactTitleContainerHtml;
		}
		if (options.message) {
			messageElem = options.message;
			options.message = reactMessageContainerHtml;
		}
		if (options.buttons) {
			let buttons = {};

			for (let rawKey in options.buttons) {
				let rawButton = options.buttons[rawKey];
				let button = {};

				let key = _.escape(rawKey);

				if (rawButton.label) {
					button.label = getReactButtonLabelContainerHtml(buttonLabelElems.length);
					buttonLabelElems.push(rawButton.label);
				}
				if (rawButton.className) {
					button.className = _.escape(rawButton.className);
				}
				if (rawButton.callback) {
					button.callback = rawButton.callback;
				}

				buttons[key] = button;
			}

			options.buttons = buttons;
		}

		return (dialog) => {
			if (titleElem) {
				ReactDOM.render(
					React.DOM.div({}, titleElem),
					dialog.find('.reactTitleContainer')[0]
				);
			}
			if (messageElem) {
				ReactDOM.render(
					React.DOM.div({}, messageElem),
					dialog.find('.reactMessageContainer')[0]
				);
			}
			buttonLabelElems.forEach((buttonLabelElem, buttonLabelIndex) => {
				ReactDOM.render(
					React.DOM.div({}, buttonLabelElem),
					dialog.find('.reactButtonLabelContainer-' + buttonLabelIndex)[0]
				);
			});
		};
	}
})();
