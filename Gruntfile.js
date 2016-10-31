/*
Copyright (c) Konode. All rights reserved.
This source code is subject to the terms of the Mozilla Public License, v. 2.0
that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

grunt task for release builds of konote
creates a 'releases' folder inside the builds directory containing compiled mac dmg and windows zip files.
*/

// TODO: bundle innosetup and codesign utility for windows?

var release = [];

module.exports = function(grunt) {
	grunt.initConfig({
		pkg: grunt.file.readJSON('package.json'),

		prompt: {
			platformType: {
				options: {
					questions: [
						{
							config: 'platformType',
							type: 'checkbox',
							message: 'Please select release platform(s) for <%= pkg.displayName %> <%= pkg.version %>',
							choices: [
								{name: ' Generic - Mac', value: 'generic-mac'},
								{name: ' Generic - Windows', value: 'generic-win'},
								{name: ' Griffin - Mac', value: 'griffin-mac'},
								{name: ' Griffin - Windows', value: 'griffin-win'},
								{name: ' St Leonards - Mac', value: 'stleonards-mac'},
								{name: ' St Leonards - Windows', value: 'stleonards-win'}
							]
						}
					],
					then: function(results) {
						release = results.platformType
					}
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
						dest: 'build/releases/temp/<%= grunt.task.current.args[0] %>/',
						filter: 'isFile',
						expand: true
					}
				],
				cwd: '/'
			},
			nodemodules: {
				expand: true,
				cwd: 'build/releases/temp/<%= grunt.task.current.args[0] %>/node_modules/',
				src: [
					'**',
					'!**/lodash-compat/**', // todo: confirm only required to support ie8...
					'!**/src/**',
					'!**/source/**',
					'!**/spec/**',
					'!**/test/**',
					'!**/tests/**',
					'!**/grunt/**',
					'!**/doc/**',
					'!**/docs/**',
					'!**/htdocs/**',
					'!**/samples/**',
					'!**/examples/**',
					'!**/example/**',
					'!**/README.md',
					'!**/readme.md',
					'!**/readme.markdown',
					'!**/changelog.md',
					'!**/CHANGELOG.md',
					'!**/changes.md',
					'!**/CHANGES.md',
					'!**/contributing.md',
					'!**/CONTRIBUTING.md',
					'!**/bower.json',
					'!**/gulpfile.js',
					'!**/gruntfile.js',
					'!**/Gruntfile.js',
					'!**/Makefile'
				],
				dest: 'build/releases/temp/<%= grunt.task.current.args[0] %>/temp_node_modules/',
			},
			production: {
				src: 'build/production.json',
				dest: 'build/releases/temp/<%= grunt.task.current.args[0] %>/src/config/production.json'
			},
			generic: {
				src: 'build/uninstaller/uninstall.exe',
				dest: 'build/releases/temp/<%= grunt.task.current.args[0] %>/uninstall.exe'
			},
			griffin: {
				files: [
					{
						src: 'customers/griffin/customer.json',
						dest: 'build/releases/temp/<%= grunt.task.current.args[0] %>/src/config/customer.json'
					},
					{
						src: 'customers/griffin/gc-logo.svg',
						dest: 'build/releases/temp/<%= grunt.task.current.args[0] %>/src/gc-logo.svg'
					}
				]
			},
			stleonards: {
				files: [
					{
						src: 'customers/st_leonards_place/customer.json',
						dest: 'build/releases/temp/<%= grunt.task.current.args[0] %>/src/config/customer.json'
					},
					{
						src: 'customers/st_leonards_place/customer-logo-lg.png',
						dest: 'build/releases/temp/<%= grunt.task.current.args[0] %>/src/stleonards-logo-lg.png'
					},
					{
						src: 'customers/st_leonards_place/customer-logo-sm.png',
						dest: 'build/releases/temp/<%= grunt.task.current.args[0] %>/src/stleonards-logo-sm.png'
					}
				]
			}
		},
		replace: {
			main: {
				src: ['build/releases/temp/<%= grunt.task.current.args[0] %>/src/start.html','build/releases/temp/<%= grunt.task.current.args[0] %>/src/main.html','build/releases/temp/<%= grunt.task.current.args[0] %>/src/main-clientSelection.html'],
				overwrite: true,
				replacements: [
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
			config: {
				src: ['build/releases/temp/<%= grunt.task.current.args[0] %>/src/config/default.json'],
				overwrite: true,
				replacements: [
					{
						from: '"devMode": true,',
						to: ''
					}
				]
			},
			griffin: {
				src: ['build/releases/temp/<%= grunt.task.current.args[0] %>/src/clientSelectionPage.coffee'],
				overwrite: true,
				replacements: [
					{
						from: 'R.img({src: Config.logoCustomerLg})',
						to: 'R.svg({width:"162.5",height:"165",viewBox:"0 0 162.5 165"},R.path({d:"M54.078 158.477L7.5 158.47V6.25H155v24.66l-5.8.795c-9.396 1.288-16.49.926-23.866-1.218-14.7-4.274-31.533 2.189-37.803 14.513-3.331 6.547-4.09 11.714-2.555 17.412 1.584 5.883 7.424 13.076 12.926 15.92l3.78 1.956-3.028 2.329c-1.666 1.28-5.418 3.325-8.337 4.543-6.733 2.81-7.105 6.522-1.206 12.034l4.11 3.84-4.086 6.073c-10.427 15.494-8.219 31.346 6.113 43.883 3.621 3.168 6.312 5.626 5.98 5.463-.331-.163-21.54.028-47.15.024zm83.08-2.798c5.935-5.05 11.845-10.926 10.47-12.3-.87-.87-2.834-.248-6.16 1.953-6.382 4.224-14.111 6.232-19.924 5.177-14.924-2.708-24.088-14.166-24.017-30.029.073-16.115 12.084-26.393 26.956-23.065 3.638.814 8.003 2.572 9.7 3.908 1.698 1.335 4.25 2.427 5.673 2.427 3.066 0 6.985-5.406 5.924-8.172-2.135-5.565-20.829-7.7-32.488-3.711-6.68 2.285-11.339 1.77-12.55-1.39-1.738-4.527 4.321-8.109 14.77-8.731 10.157-.606 20.005-5.609 24.984-12.693 4.914-6.99 5.852-17.41 2.198-24.41l-2.47-4.731 4.836.285c3.259.193 5.667-.467 7.387-2.024l2.553-2.31V158.454l-10.577.029-10.555-.004zm-28.714-81.39C97.592 68.4 96.55 43.525 106.872 36.762c3.983-2.61 11.085-2.57 15.136.085 9.779 6.408 10.825 30.9 1.596 37.365-3.595 2.517-10.595 2.553-15.16.077z", fill:"#0076bf"}))'
					}
				]
			},
			bootstrap: {
				src: ['build/releases/temp/<%= grunt.task.current.args[0] %>/lib/bootstrap/dist/js/bootstrap.min.js'],
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
				cwd: 'build/releases/temp/nwjs-<%= grunt.task.current.args[0] %>/konote-win-ia32',
				cmd: 'zip -r --quiet ../../../konote-<%= pkg.version %>-<%= grunt.task.current.args[0] %>.zip *'
			},
			codesign: {
				cwd: 'build/releases/temp/nwjs-<%= grunt.task.current.args[0] %>/konote-osx-x64',
				cmd: '../../../../codesign-osx.sh'
			},
			npm: {
				cwd: 'build/releases/temp/<%= grunt.task.current.args[0] %>',
				cmd: 'npm install --production --no-optional'
			},
			renamemodules: {
				cwd: 'build/releases/temp/<%= grunt.task.current.args[0] %>',
				cmd: 'mv temp_node_modules node_modules'
			},
			test: {
				cmd: 'npm test'
			},
			nwjswin: {
				cwd: 'build/releases/temp/',
				cmd: 'nwb nwbuild -v 0.17.6 -p win32 --win-ico ./<%= grunt.task.current.args[0] %>/src/icon.ico -o ./nwjs-<%= grunt.task.current.args[0] %>/ --side-by-side ./<%= grunt.task.current.args[0] %>/'
			},
			nwjsosx: {
				cwd: 'build/releases/temp/',
				cmd: 'nwb nwbuild -v 0.17.6 -p osx64 --mac-icns ./<%= grunt.task.current.args[0] %>/src/icon.icns -o ./nwjs-<%= grunt.task.current.args[0] %>/ --side-by-side ./<%= grunt.task.current.args[0] %>/'
			}
		},
		appdmg: {
			main: {
				options: {
					title: 'KoNote-<%= pkg.version %>',
					background: 'build/releases/temp/<%= grunt.task.current.args[0] %>/src/background.tiff', 'icon-size': 104,
					contents: [
						{x: 130, y: 150, type: 'file', path: 'build/releases/temp/nwjs-<%= grunt.task.current.args[0] %>/konote-osx-x64/konote.app'},
						{x: 320, y: 150, type: 'link', path: '/Applications'}
					]
				},
				dest: 'build/releases/konote-<%= pkg.version %>-<%= grunt.task.current.args[0] %>.dmg'
			}
		},
		stylus: {
			compile: {
				files: {
					'build/releases/temp/<%= grunt.task.current.args[0] %>/src/main.css': 'build/releases/temp/<%= grunt.task.current.args[0] %>/src/main.styl'
				}
			}
		},
		coffee: {
			compileMultiple: {
				options: {
					sourceMap: true
				},
				expand: true,
				cwd: 'build/releases/temp/<%= grunt.task.current.args[0] %>/src',
				src: ['**/*.coffee'],
				dest: 'build/releases/temp/<%= grunt.task.current.args[0] %>/src',
				extDot: 'last',
				ext: '.js'
			}
		},
		clean: {
			coffee: [
				"build/releases/temp/<%= grunt.task.current.args[0] %>/src/**/*.coffee"
			],
			styl: [
				"build/releases/temp/<%= grunt.task.current.args[0] %>/src/**/*.styl"
			],
			temp: [
				"build/releases/temp/**/*"
			],
			nodemodules: [
				"build/releases/temp/<%= grunt.task.current.args[0] %>/node_modules/**"
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
					cwd: 'build/releases/temp/<%= grunt.task.current.args[0] %>/src',
					src: ['**/*.js', '!layeredComponentMixin.js', '!start.js', '!config/index.js'],
					dest: 'build/releases/temp/<%= grunt.task.current.args[0] %>/src',
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
	if (process.platform == 'darwin') {
		grunt.loadNpmTasks('grunt-appdmg');
	}

	grunt.registerTask('build', function() {
		grunt.task.run('prompt');
		grunt.task.run('release');
	});

	grunt.registerTask('release', function() {
		grunt.task.run('clean:temp');
		grunt.task.run('exec:test');
		release.forEach(function(entry) {
			grunt.task.run('copy:main:'+entry);
			grunt.task.run('replace:main:'+entry);
			grunt.task.run('replace:config:'+entry);
			grunt.task.run('copy:production:'+entry);
			if (entry == "generic-win") {
				grunt.task.run('copy:generic:'+entry);
			}
			if (entry == "griffin-mac" || entry == "griffin-win") {
				grunt.task.run('copy:griffin:'+entry);
				grunt.task.run('replace:griffin:'+entry);
			}
			if (entry == "stleonards-mac" || entry == "stleonards-win") {
				grunt.task.run('copy:stleonards:'+entry);
			}
			grunt.task.run('exec:npm:'+entry);
			grunt.task.run('copy:nodemodules:'+entry);
			grunt.task.run('clean:nodemodules:'+entry);
			grunt.task.run('exec:renamemodules:'+entry);
			grunt.task.run('replace:bootstrap:'+entry);
			grunt.task.run('stylus:compile:'+entry);
			grunt.task.run('coffee:compileMultiple:'+entry);
			grunt.task.run('uglify:all:'+entry);
			grunt.task.run('clean:coffee:'+entry);
			grunt.task.run('clean:styl:'+entry);
			if (entry.includes("win")) {
				grunt.task.run('exec:nwjswin:'+entry);
				grunt.task.run('exec:zip:'+entry);
			}
			if (entry.includes("mac")) {
				grunt.task.run('exec:nwjsosx:'+entry);
				if (process.platform == 'darwin') {
					grunt.task.run('exec:codesign:'+entry);
					grunt.task.run('appdmg:main:'+entry);
				}
			}
		});
		grunt.task.run('clean:temp');
	});
};
