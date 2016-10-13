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
				src: ['build/releases/temp/<%= grunt.task.current.args[0] %>/src/main.html'],
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
			start: {
				src: ['build/releases/temp/<%= grunt.task.current.args[0] %>/src/start.html'],
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
				cmd: 'nwb nwbuild -v 0.18.0 -p win32 --win-ico ./<%= grunt.task.current.args[0] %>/src/icon.ico -o ./nwjs-<%= grunt.task.current.args[0] %>/ --side-by-side ./<%= grunt.task.current.args[0] %>/'
			},
			nwjsosx: {
				cwd: 'build/releases/temp/',
				cmd: 'nwb nwbuild -v 0.18.0 -p osx64 --mac-icns ./<%= grunt.task.current.args[0] %>/src/icon.icns -o ./nwjs-<%= grunt.task.current.args[0] %>/ --side-by-side ./<%= grunt.task.current.args[0] %>/'
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
			grunt.task.run('replace:start:'+entry);
			grunt.task.run('replace:config:'+entry);
			grunt.task.run('copy:production:'+entry);
			if (entry == "generic-win") {
				grunt.task.run('copy:generic:'+entry);
			}
			if (entry == "griffin-mac" || entry == "griffin-win") {
				grunt.task.run('copy:griffin:'+entry);
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
