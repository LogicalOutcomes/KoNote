/*
Copyright (c) Konode. All rights reserved.
This source code is subject to the terms of the Mozilla Public License, v. 2.0
that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

grunt task for release builds of konote
creates a 'dist' directory containing compiled mac dmg and windows zip files.
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
								{name: ' Generic - Mac', value: 'mac'},
								{name: ' Generic - Windows', value: 'win'},
								{name: ' Generic - Windows - SDK', value: 'SDK'},
								{name: ' Griffin - Mac', value: 'griffin-mac'},
								{name: ' Griffin - Windows', value: 'griffin-win'}
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
				cwd: 'dist/temp/nwjs-<%= grunt.task.current.args[0] %>/uninstall-win-ia32/',
				src: 'uninstall.exe',
				dest: 'dist/temp/nwjs-<%= grunt.task.current.args[0] %>/konote-win-ia32/'
			},
			nodemodules: {
				expand: true,
				dot: true,
				nocase: true,
				cwd: 'dist/temp/<%= grunt.task.current.args[0] %>/node_modules/',
				src: [
					'**',
					'!**/AUTHOR*',
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
					'!**/__tests__/**',
					'!**/*.yml'
				],
				dest: 'dist/temp/<%= grunt.task.current.args[0] %>/temp_node_modules/',
			},
			production: {
				src: 'build/production.json',
				dest: 'dist/temp/<%= grunt.task.current.args[0] %>/src/config/production.json'
			},
			generic: {
				src: 'build/uninstaller/uninstall.exe',
				dest: 'dist/temp/<%= grunt.task.current.args[0] %>/uninstall.exe'
			},
			griffin: {
				files: [
					{
						src: 'customers/griffin/customer.json',
						dest: 'dist/temp/<%= grunt.task.current.args[0] %>/src/config/customer.json'
					},
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
						to: '<script>process.env.NODE_ENV = "production"; require("./main").init(window);</script>'
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
				cwd: 'dist/temp/nwjs-<%= grunt.task.current.args[0] %>/konote-win-ia32',
				cmd: 'zip -r --quiet ../../../konote-<%= pkg.version %>-<%= grunt.task.current.args[0] %>.zip *'
			},
			setup :{
				cwd: 'dist/temp/nwjs-<%= grunt.task.current.args[0] %>/konote-win-ia32',
				cmd: '../../../../build/innosetup.sh ../../../../build/konote-innosetup.iss'
			},
			codesign: {
				cwd: 'dist/temp/nwjs-<%= grunt.task.current.args[0] %>/konote-osx-x64',
				cmd: '../../../../build/codesign-osx.sh'
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
				cwd: 'dist/temp/',
				cmd: 'nwb nwbuild -v <%= (pkg.devDependencies.nw).substring(0, 6) %> -p win32 -o ./nwjs-<%= grunt.task.current.args[0] %>/ ./uninstaller'
			},
			nwjswin: {
				cwd: 'dist/temp/',
				cmd: 'nwb nwbuild -v <%= (pkg.devDependencies.nw).substring(0, 6) %> -p win32 --win-ico ./<%= grunt.task.current.args[0] %>/src/icon.ico -o ./nwjs-<%= grunt.task.current.args[0] %>/ --side-by-side ./<%= grunt.task.current.args[0] %>/'
			},
			nwjswinSDK: {
				cwd: 'dist/temp/',
				cmd: 'nwb nwbuild -v <%= pkg.devDependencies.nw %> -p win32 --win-ico ./<%= grunt.task.current.args[0] %>/src/icon.ico -o ./nwjs-<%= grunt.task.current.args[0] %>/ --side-by-side ./<%= grunt.task.current.args[0] %>/'
			},
			nwjsosx: {
				cwd: 'dist/temp/',
				cmd: 'nwb nwbuild -v <%= (pkg.devDependencies.nw).substring(0, 6) %> -p osx64 --mac-icns ./<%= grunt.task.current.args[0] %>/src/icon.icns -o ./nwjs-<%= grunt.task.current.args[0] %>/ --side-by-side ./<%= grunt.task.current.args[0] %>/'
			}
		},
		appdmg: {
			main: {
				options: {
					title: 'KoNote-<%= pkg.version %>',
					background: 'dist/temp/<%= grunt.task.current.args[0] %>/src/background.tiff', 'icon-size': 104,
					contents: [
						{x: 130, y: 150, type: 'file', path: 'dist/temp/nwjs-<%= grunt.task.current.args[0] %>/konote-osx-x64/konote.app'},
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
					src: ['**/*.js', '!layeredComponentMixin.js', '!start.js', '!config/index.js'],
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
			grunt.task.run('copy:eula:'+entry);
			if (entry == "win") {
				//grunt.task.run('copy:generic:'+entry);
				grunt.task.run('copy:uninstaller:'+entry);
				grunt.task.run('exec:npmUninstaller:'+entry);
				grunt.task.run('exec:nwjsuninstaller:'+entry);
			}
			if (entry == "griffin-mac" || entry == "griffin-win") {
				grunt.task.run('copy:griffin:'+entry);
				grunt.task.run('replace:griffin:'+entry);
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
				grunt.task.run('copy:uninstallerbinary:'+entry);
				// codesign and create setup file
				grunt.task.run('exec:setup:'+entry)
				grunt.task.run('exec:zip:'+entry);
			}
			if (entry.includes("SDK")) {
				grunt.task.run('exec:nwjswinSDK:'+entry);
				grunt.task.run('copy:uninstallerbinary:'+entry);
				// codesign and create setup file
				//grunt.task.run('exec:setup:'+entry)
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
