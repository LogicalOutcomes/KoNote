/*
Copyright (c) Konode. All rights reserved.
This source code is subject to the terms of the Mozilla Public License, v. 2.0
that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

grunt task for release builds of konote
creates a 'dist' directory containing compiled mac dmg and windows zip files.
*/

// TODO: bundle innosetup and codesign utility for windows?

const _ = require('underscore');
const Fs = require('fs');
const Path = require('path');

const SUPPORTED_PLATFORMS = [
	// [id, name]
	// id must be file path safe and not include hyphens
	['mac', 'Mac'],
	['win', 'Windows'],
	['winsdk', 'Windows (SDK)'],
];
const SUPPORTED_PLATFORM_IDS = SUPPORTED_PLATFORMS.map(function (p) {
	return p[0];
});

const SUPPORTED_CUSTOMER_IDS =
	// Include null customerId to indicate default/generic configuration
	[null].concat(
		Fs.readdirSync('customers')
			.filter(function (dirName) {
				return Fs.existsSync(Path.join('customers', dirName, 'customer.json'));
			})
	);

function customerIdToDisplayName(customerId) {
	if (customerId === null) {
		return 'Generic';
	}

	return customerId.split('_').map(capitalizeWord).join(' ');
}

function capitalizeWord(word) {
	return word.charAt(0).toUpperCase() + word.slice(1);
}


var releases = [];

module.exports = function(grunt) {
	grunt.initConfig({
		pkg: grunt.file.readJSON('package.json'),

		prompt: {
			releases: {
				options: {
					questions: [
						{
							config: 'releases',
							type: 'checkbox',
							message: 'Please select release platform(s) for <%= pkg.displayName %> <%= pkg.version %>',
							choices: _.flatten(SUPPORTED_CUSTOMER_IDS.map(function (customerId) {
								const customerDisplayName = customerIdToDisplayName(customerId);

								return SUPPORTED_PLATFORMS.map(function ([platformId, platformName]) {
									return {
										name: ' ' + customerDisplayName + ' - ' + platformName,
										value: [platformId, customerId],
									};
								});
							}), true),
						}
					],
					then: function(results) {
						// Save in global for later use
						releases = results.releases;
					}
				}
			},
			codesignPassword: {
				options: {
					questions: [
						{
							config: 'codesignPassword',
							type: 'password',
							message: 'Please enter password for windows codesigning key file'
						}
					]
				}
			}
		},
		copy: {
			main: {
				files: [
					{
						src: [
							'package.json',
							'src/**',
							'lib/**',
							'!src/config/develop.json'
						],
						dest: 'dist/temp/<%= grunt.task.current.args[0] %>/',
						filter: 'isFile',
						expand: true
					}
				],
				cwd: '/'
			},
			eula: {
				src: 'build/eula.txt',
				dest: 'dist/temp/<%= grunt.task.current.args[0] %>/eula.txt'
			},
			uninstaller: {
				expand: true,
				cwd: 'build/uninstaller/',
				src: [
					'package.json',
					'index.html'
				],
				dest: 'dist/temp/uninstaller/'
			},
			uninstallerbinary: {
				expand: true,
				cwd: 'dist/temp/uninstaller/dist/uninstall-win-x64/',
				src: 'uninstall.exe',
				dest: 'dist/temp/<%= grunt.task.current.args[0] %>/dist/KoNote-win-x64/'
			},
			nodemodules: {
				expand: true,
				dot: true,
				nocase: true,
				cwd: 'dist/temp/<%= grunt.task.current.args[0] %>/node_modules/',
				src: [
					'**',
					'!**/AUTHOR*',
					'!**/assets*',
					'!**/bower.json',
					'!**/changelog*',
					'!**/changes*',
					'!**/contributing*',
					'!**/coverage/**',
					'!**/doc/**',
					'!**/docs/**',
					'!**/example*',
					'!**/example/**',
					'!**/examples/**',
					'!**/grunt/**',
					'!**/Gruntfile.js',
					'!**/gulpfile.js',
					'!**/history.md',
					'!**/htdocs/**',
					'!**/*ignore',
					'!**/images/**',
					'!**/LICENSE*',
					'!**/LICENCE*',
					'!**/lodash-compat/**',
					'!**/Makefile*',
					'!**/man/**',
					'!**/README*',
					'!**/release-notes*',
					'!**/samples/**',
					'!**/source/**',
					'!**/spec/**',
					'!**/src/**',
					'!**/test.js',
					'!**/test/**',
					'!**/tests/**',
					'!**/website/**',
					'!**/__tests__/**',
					'!**/*.ignore',
					'!**/*.editorconfig',
					'!**/*.eslintrc',
					'!**/*.gitattributes',
					'!**/*.jshintrc',
					'!**/*.jst',
					'!**/*.md',
					'!**/*.nyc_output',
					'!**/*.ts',
					'!**/*.yml'
				],
				dest: 'dist/temp/<%= grunt.task.current.args[0] %>/temp_node_modules/'
			},
			production: {
				src: 'build/production.json',
				dest: 'dist/temp/<%= grunt.task.current.args[0] %>/src/config/production.json'
			},
			generic: {
				src: 'build/uninstaller/uninstall.exe',
				dest: 'dist/temp/<%= grunt.task.current.args[0] %>/uninstall.exe'
			},
			customerConfig: {
				src: 'customers/<%= grunt.task.current.args[1] %>/customer.json',
				dest: 'dist/temp/<%= grunt.task.current.args[0] %>/src/config/customer.json'
			},
			griffin: {
				files: [
					{
						src: 'customers/griffin/gc-logo.svg',
						dest: 'dist/temp/<%= grunt.task.current.args[0] %>/src/gc-logo.svg'
					}
				]
			}
		},
		replace: {
			main: {
				src: ['dist/temp/<%= grunt.task.current.args[0] %>/src/start.html','dist/temp/<%= grunt.task.current.args[0] %>/src/main.html','dist/temp/<%= grunt.task.current.args[0] %>/src/main-clientSelection.html'],
				overwrite: true,
				replacements: [
					{
						from: '<script src="start.js"></script>',
						to: '<script>require("./main").init(window);</script>'
					},
					{
						from: 'react-with-addons.js',
						to: 'react-with-addons.min.js'
					},
					{
						from: 'react-dom-server.js',
						to: 'react-dom-server.min.js'
					},
					{
						from: 'react-dom.js',
						to: 'react-dom.min.js'
					},
					{
						from: '<style id="main-css">/* see start.js */</style>',
						to: '<link rel="stylesheet" href="main.css">'
					}
				]
			},
			start: {
				src: ['dist/temp/<%= grunt.task.current.args[0] %>/src/start.html'],
				overwrite: true,
				replacements: [
					{
						from: '<script src="startOnce.js"></script>',
						to: '<script>process.env.NODE_ENV = "production";</script><script src="startOnce.js"></script>'
					}
				]
			},
			config: {
				src: ['dist/temp/<%= grunt.task.current.args[0] %>/src/config/default.json'],
				overwrite: true,
				replacements: [
					{
						from: '"devMode": true,',
						to: ''
					}
				]
			},
			griffin: {
				src: ['dist/temp/<%= grunt.task.current.args[0] %>/src/clientSelectionPage.coffee'],
				overwrite: true,
				replacements: [
					{
						from: 'R.img({src: Config.logoCustomerLg})',
						to: 'R.svg({width:"162.5",height:"165",viewBox:"0 0 162.5 165"},R.path({d:"M54.078 158.477L7.5 158.47V6.25H155v24.66l-5.8.795c-9.396 1.288-16.49.926-23.866-1.218-14.7-4.274-31.533 2.189-37.803 14.513-3.331 6.547-4.09 11.714-2.555 17.412 1.584 5.883 7.424 13.076 12.926 15.92l3.78 1.956-3.028 2.329c-1.666 1.28-5.418 3.325-8.337 4.543-6.733 2.81-7.105 6.522-1.206 12.034l4.11 3.84-4.086 6.073c-10.427 15.494-8.219 31.346 6.113 43.883 3.621 3.168 6.312 5.626 5.98 5.463-.331-.163-21.54.028-47.15.024zm83.08-2.798c5.935-5.05 11.845-10.926 10.47-12.3-.87-.87-2.834-.248-6.16 1.953-6.382 4.224-14.111 6.232-19.924 5.177-14.924-2.708-24.088-14.166-24.017-30.029.073-16.115 12.084-26.393 26.956-23.065 3.638.814 8.003 2.572 9.7 3.908 1.698 1.335 4.25 2.427 5.673 2.427 3.066 0 6.985-5.406 5.924-8.172-2.135-5.565-20.829-7.7-32.488-3.711-6.68 2.285-11.339 1.77-12.55-1.39-1.738-4.527 4.321-8.109 14.77-8.731 10.157-.606 20.005-5.609 24.984-12.693 4.914-6.99 5.852-17.41 2.198-24.41l-2.47-4.731 4.836.285c3.259.193 5.667-.467 7.387-2.024l2.553-2.31V158.454l-10.577.029-10.555-.004zm-28.714-81.39C97.592 68.4 96.55 43.525 106.872 36.762c3.983-2.61 11.085-2.57 15.136.085 9.779 6.408 10.825 30.9 1.596 37.365-3.595 2.517-10.595 2.553-15.16.077z", fill:"#0076bf"}))'
					}
				]
			},
			bootstrap: {
				src: ['dist/temp/<%= grunt.task.current.args[0] %>/lib/bootstrap/dist/js/bootstrap.min.js'],
				overwrite: true,
				replacements: [
					{
						from: 'TRANSITION_DURATION=300',
						to: 'TRANSITION_DURATION=100'
					}
				]
			}
		},
		exec: {
			zip: {
				cwd: 'dist/temp/<%= grunt.task.current.args[0] %>/dist/KoNote-win-x64',
				cmd: 'zip -r --quiet ../../../../konote-<%= pkg.version %>-<%= grunt.task.current.args[0] %>.zip *'
			},
			setup :{
				cwd: 'dist/temp/<%= grunt.task.current.args[0] %>/dist/KoNote-win-x64',
				cmd: '../../../../../build/innosetup.sh ../../../../../build/konote-innosetup.iss'
			},
			codesign: {
				cwd: 'dist/temp/<%= grunt.task.current.args[0] %>/dist/KoNote-mac-x64',
				cmd: '../../../../../build/codesign-osx.sh'
			},
			codesignWin: {
				cwd: 'dist/temp/<%= grunt.task.current.args[0] %>/dist/KoNote-win-x64',
				cmd: '../../../../../build/codesign-win.sh <%= grunt.config("codesignPassword") %> KoNote.exe'
			},
			npm: {
				cwd: 'dist/temp/<%= grunt.task.current.args[0] %>',
				cmd: 'npm install --production --no-optional'
			},
			npmUninstaller: {
				cwd: 'dist/temp/uninstaller',
				cmd: 'npm install --production --no-optional'
			},
			renamemodules: {
				cwd: 'dist/temp/<%= grunt.task.current.args[0] %>',
				cmd: 'mv temp_node_modules node_modules'
			},
			test: {
				cmd: 'npm test'
			},
			nwjsuninstaller: {
				cwd: 'dist/temp/uninstaller',
				cmd: '../../../node_modules/.bin/build --tasks win-x64 .'
			},
			nwjswin: {
				cwd: 'dist/temp/<%= grunt.task.current.args[0] %>/',
				cmd: '../../../node_modules/.bin/build --tasks win-x64 .'
			},
			nwjswinSDK: {
				cwd: 'dist/temp/',
				cmd: 'nwb nwbuild -v <%= pkg.devDependencies.nw %> -p win64 --win-ico ./<%= grunt.task.current.args[0] %>/src/icon.ico -o ./nwjs-<%= grunt.task.current.args[0] %>/ --side-by-side ./<%= grunt.task.current.args[0] %>/'
			},
			nwjsosx: {
				cwd: 'dist/temp/<%= grunt.task.current.args[0] %>/',
				cmd: '../../../node_modules/.bin/build --tasks mac-x64 .'
			}
		},
		appdmg: {
			main: {
				options: {
					title: 'KoNote-<%= pkg.version %>',
					background: 'dist/temp/<%= grunt.task.current.args[0] %>/src/background.tiff', 'icon-size': 104,
					contents: [
						{x: 130, y: 150, type: 'file', path: 'dist/temp/<%= grunt.task.current.args[0] %>/dist/KoNote-mac-x64/konote.app'},
						{x: 320, y: 150, type: 'link', path: '/Applications'}
					]
				},
				dest: 'dist/konote-<%= pkg.version %>-<%= grunt.task.current.args[0] %>.dmg'
			}
		},
		stylus: {
			compile: {
				files: {
					'dist/temp/<%= grunt.task.current.args[0] %>/src/main.css': 'dist/temp/<%= grunt.task.current.args[0] %>/src/main.styl'
				}
			}
		},
		coffee: {
			compileMultiple: {
				options: {
					sourceMap: true
				},
				expand: true,
				cwd: 'dist/temp/<%= grunt.task.current.args[0] %>/src',
				src: ['**/*.coffee'],
				dest: 'dist/temp/<%= grunt.task.current.args[0] %>/src',
				extDot: 'last',
				ext: '.js'
			}
		},
		clean: {
			coffee: [
				"dist/temp/<%= grunt.task.current.args[0] %>/src/**/*.coffee"
			],
			styl: [
				"dist/temp/<%= grunt.task.current.args[0] %>/src/**/*.styl"
			],
			temp: [
				"dist/temp/"
			],
			nodemodules: [
				"dist/temp/<%= grunt.task.current.args[0] %>/node_modules/**"
			]
		},
		uglify: {
			options: {
				banner: "require('source-map-support').install({environment: 'node'});",
				dead_code: true,
				unused: true,
				loops: true,
				conditionals: true,
				booleans: true,
				drop_console: true,
				screwIE8: true,
				sourceMap: true,
				sourceMapIn: function(path) {
					return path+".map";
				}
			},
			all: {
				files: [{
					expand: true,
					cwd: 'dist/temp/<%= grunt.task.current.args[0] %>/src',
					src: ['**/*.js', '!layeredComponentMixin.js', '!start.js', '!startOnce.js', '!bootbox-noxss.js', '!config/index.js'],
					dest: 'dist/temp/<%= grunt.task.current.args[0] %>/src',
					ext: '.js'
				}]
			}
    	}
	});

	// load the plugins
	grunt.loadNpmTasks('grunt-exec');
	grunt.loadNpmTasks('grunt-contrib-copy');
	grunt.loadNpmTasks('grunt-text-replace');
	grunt.loadNpmTasks('grunt-prompt');
	grunt.loadNpmTasks('grunt-contrib-stylus');
	grunt.loadNpmTasks('grunt-contrib-coffee');
	grunt.loadNpmTasks('grunt-contrib-clean');
	grunt.loadNpmTasks('grunt-contrib-uglify');
	if (process.platform === 'darwin') {
		grunt.loadNpmTasks('grunt-appdmg');
	}

	grunt.registerTask('build', function () {
		if (process.env.RELEASES) {
			// e.g. win:griffin,mac:griffin,mac,win
			releases = process.env.RELEASES.split(',').map(function (r) {
				const parts = r.split(':');

				if (parts.length === 1) {
					return [parts[0], null];
				}
				if (parts.length === 2) {
					return parts;
				}

				throw new Error("could not parse RELEASES env var");
			});

			releases.forEach(function (r) {
				if (!SUPPORTED_PLATFORM_IDS.includes(r[0])) {
					throw new Error("RELEASES env var has unknown platform ID " + JSON.stringify(r[0]));
				}

				if (!SUPPORTED_CUSTOMER_IDS.includes(r[1])) {
					throw new Error("RELEASES env var has unknown customer ID " + JSON.stringify(r[1]));
				}
			});
		} else {
			grunt.task.run('prompt:releases');
		}
		grunt.task.run('build-releases');
	});

	grunt.registerTask('build-all-customers', function () {
		if (!process.env.PLATFORM) {
			throw new Error("build-all-customers requires env var PLATFORM");
		}

		const platformId = process.env.PLATFORM;

		if (!SUPPORTED_PLATFORM_IDS.includes(platformId)) {
			throw new Error("unknown platform ID " + JSON.stringify(platformId));
		}

		releases = SUPPORTED_CUSTOMER_IDS.map(function (customerId) {
			return [platformId, customerId];
		});

		grunt.task.run('build-releases');
	});

	// internal use only
	grunt.registerTask('build-releases', function () {
		grunt.task.run('clean:temp');
		grunt.task.run('exec:test');

		releases.forEach(function ([platformId, customerId]) {
			var releaseId = customerId ? customerId + '-' + platformId : platformId;

			grunt.task.run('copy:main:' + releaseId);
			grunt.task.run('replace:main:' + releaseId);
			grunt.task.run('replace:start:' + releaseId);
			grunt.task.run('replace:config:' + releaseId);
			grunt.task.run('copy:production:' + releaseId);
			grunt.task.run('copy:eula:' + releaseId);

			if (platformId === "win") {
				//grunt.task.run('copy:generic:' + releaseId);

				// Copy uninstaller app code to /dist
				grunt.task.run('copy:uninstaller:' + releaseId);

				// Run npm install on uninstaller app code in /dist
				grunt.task.run('exec:npmUninstaller:' + releaseId);

				// Run NW.js builder on uninstaller app to produce .exe
				grunt.task.run('exec:nwjsuninstaller:' + releaseId);
			}

			// Add customer-specific configuration file if not a generic build
			if (customerId) {
				grunt.task.run('copy:customerConfig:' + releaseId + ':' + customerId);
			}

			// Griffin-specific customizations
			// TODO All configurations should be done through customer.json
			if (customerId === "griffin") {
				grunt.task.run('copy:griffin:' + releaseId);
				grunt.task.run('replace:griffin:' + releaseId);
			}

			grunt.task.run('exec:npm:' + releaseId);
			grunt.task.run('copy:nodemodules:' + releaseId);
			grunt.task.run('clean:nodemodules:' + releaseId);
			grunt.task.run('exec:renamemodules:' + releaseId);
			grunt.task.run('replace:bootstrap:' + releaseId);
			grunt.task.run('stylus:compile:' + releaseId);
			grunt.task.run('coffee:compileMultiple:' + releaseId);
			grunt.task.run('uglify:all:' + releaseId);
			grunt.task.run('clean:coffee:' + releaseId);
			grunt.task.run('clean:styl:' + releaseId);
			if (platformId === "win") {
				grunt.task.run('exec:nwjswin:' + releaseId);
				grunt.task.run('copy:uninstallerbinary:' + releaseId);
				// codesign and create setup file
				//grunt.task.run('prompt:codesignPassword');
				//grunt.task.run('exec:codesignWin:' + releaseId);
				//grunt.task.run('exec:setup:' + releaseId);
				grunt.task.run('exec:zip:' + releaseId);
			}
			if (platformId === "winsdk") {
				grunt.task.run('exec:nwjswinSDK:' + releaseId);
				grunt.task.run('copy:uninstallerbinary:' + releaseId);
				// codesign and create setup file
				//grunt.task.run('exec:setup:' + releaseId)
				grunt.task.run('exec:zip:' + releaseId);
			}
			if (platformId === "mac") {
				grunt.task.run('exec:nwjsosx:' + releaseId);
				if (process.platform === 'darwin') {
					grunt.task.run('exec:codesign:' + releaseId);
					grunt.task.run('appdmg:main:' + releaseId);
				}
			}
		});
		grunt.task.run('clean:temp');
	});
};
