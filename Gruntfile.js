/*
Copyright (c) Konode. All rights reserved.
This source code is subject to the terms of the Mozilla Public License, v. 2.0 
that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

grunt task for release builds of konote
creates a 'releases' folder inside the builds directory containing compiled mac dmg and windows zip files.

note[1]: requires forked nw-builder module (disables merging win build with the nw exe):
https://github.com/speedskater/node-webkit-builder

note[2]: mainly tested on OSX; nwjs recommends building on native OS, so ymmv
*/

// TODO:
// bundle innosetup, resource_hacker and codesign utility for windows?

var win = null;
var mac = null;
var generic = null;
var griffin = null;

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
							message: 'Please select release platform(s)',
							choices: [
								{name: ' Mac', value: 'osx64'},
								{name: ' Windows', value: 'win32'}
							]
						}
					],
					then: function(results) {
						if (results.platformType.indexOf('osx64') !== -1) {
							mac = 1;
						}
						if (results.platformType.indexOf('win32') !== -1) {
							win = 1;
						}
					}
				}
			},
			releaseType: {
				options: {
					questions: [
						{
							config: 'releaseType',
							type: 'checkbox',
							message: 'Please select release type(s)',
							choices: [
								{name: ' Generic', value: 'generic'},
								{name: ' Griffin', value: 'griffin'}
							]
						}
					],
					then: function(results) {
						if (results.releaseType.indexOf('griffin') !== -1) {
							griffin = 1;
						}
						if (results.releaseType.indexOf('generic') !== -1) {
							generic = 1;
						}
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
							'node_modules/**',
							'!node_modules/nw/**',
							'!node_modules/nodewebkit/**',
							'!node_modules/grunt*/**',
							'!node_modules/chokidar*/**',
							'!src/config/develop.json'
						],
						dest: 'build/releases/temp/<%= grunt.task.current.args[0] %>/',
						filter: 'isFile',
						expand: true
					}
				],
				cwd: '/'
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
			}
		},
		nwjs: {
			mac: {
				options: {
					appName: '<%= pkg.displayName %>',
					//macCredits: 'path-to-file',
					macIcns: 'build/releases/temp/<%= grunt.task.current.args[0] %>/src/icon.icns',
					version: '<%= pkg.dependencies.nodewebkit %>',
					platforms: ['osx64'],
					buildType: 'default',
					buildDir: 'build/releases/temp/nwjs/<%= grunt.task.current.args[0] %>',
					cacheDir: 'build/releases/temp/cache/<%= grunt.task.current.args[0] %>',
					macZip: false,
					forceDownload: true
				},
				src: ['build/releases/temp/<%= grunt.task.current.args[0] %>/**']
			},
			win: {
				options: {
					appName: '<%= pkg.displayName %>',
					version: '<%= pkg.dependencies.nodewebkit %>',
					platforms: ['win32'],
					buildType: 'default',
					buildDir: 'build/releases/temp/nwjs/<%= grunt.task.current.args[0] %>',
					cacheDir: 'build/releases/temp/cache/<%= grunt.task.current.args[0] %>',
					winZip: false,
					forceDownload: true
				},
				src: ['build/releases/temp/<%= grunt.task.current.args[0] %>/**']
			}
    	},
		exec: {
			zip: {
				cwd: 'build/releases/temp/nwjs/<%= grunt.task.current.args[0] %>/KoNote/win32',
				cmd: 'zip -r --quiet ../../../../../konote-<%= pkg.version %>-<%= grunt.task.current.args[0] %>.zip *'
			},
			codesign: {
				cwd: 'build/releases/temp/nwjs/<%= grunt.task.current.args[0] %>/KoNote/osx64',
				cmd: '../../../../../../codesign-osx.sh'
			}
		},
		appdmg: {
			main: {
				options: {
					title: 'KoNote-<%= pkg.version %>',
					//icon: 'build/releases/temp/<%= grunt.task.current.args[0] %>/src/icon.icns',
					background: 'build/releases/temp/<%= grunt.task.current.args[0] %>/src/background.tiff', 'icon-size': 104,
					contents: [
						{x: 130, y: 150, type: 'file', path: 'build/releases/temp/nwjs/<%= grunt.task.current.args[0] %>/KoNote/osx64/KoNote.app'},
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
				ext: '.js'
			}
		},
		clean: {
			coffee: [
				"build/releases/temp/<%= grunt.task.current.args[0] %>/src/**/*.coffee"
			],
			temp: [
				"build/releases/temp"
			]
		}
	});
	
	// load the plugins
	grunt.loadNpmTasks('grunt-nw-builder');
	grunt.loadNpmTasks('grunt-exec');
	grunt.loadNpmTasks('grunt-contrib-copy');
	grunt.loadNpmTasks('grunt-prompt');
	grunt.loadNpmTasks('grunt-contrib-stylus');
	grunt.loadNpmTasks('grunt-contrib-coffee');
	grunt.loadNpmTasks('grunt-contrib-clean');
	
	// if on osx, we can use appdmg
	if (process.platform == 'darwin') {
		grunt.loadNpmTasks('grunt-appdmg');
	}
	
	grunt.registerTask('build', function() {
			grunt.task.run('prompt');
			grunt.task.run('release')
	});
	
	grunt.registerTask('release', function() {
		grunt.task.run('clean:temp');
		
		if (win) {
			if (generic) {
				// do win generic build
				grunt.task.run('copy:main:win-generic');
				grunt.task.run('copy:production:win-generic');
				grunt.task.run('copy:generic:win-generic');
				grunt.task.run('stylus:compile:win-generic');
				grunt.task.run('coffee:compileMultiple:win-generic');
				grunt.task.run('clean:coffee:win-generic');
				grunt.task.run('nwjs:win:win-generic');
				grunt.task.run('exec:zip:win-generic');
			}
			if (griffin) {
				// do win griffin build
				grunt.task.run('copy:main:win-griffin');
				grunt.task.run('copy:production:win-griffin');
				grunt.task.run('copy:griffin:win-griffin');
				grunt.task.run('stylus:compile:win-griffin');
				grunt.task.run('coffee:compileMultiple:win-griffin');
				grunt.task.run('clean:coffee:win-griffin');
				grunt.task.run('nwjs:win:win-griffin');
				grunt.task.run('exec:zip:win-griffin');
			}
		}
		if (mac) {
			if (generic) {
				// do mac generic build
				console.log(process.cwd());
				grunt.task.run('copy:main:mac-generic');
				grunt.task.run('copy:production:mac-generic');
				grunt.task.run('stylus:compile:mac-generic');
				grunt.task.run('coffee:compileMultiple:mac-generic');
				grunt.task.run('clean:coffee:mac-generic');
				grunt.task.run('nwjs:mac:mac-generic');
				grunt.task.run('exec:codesign:mac-generic');
				if (process.platform == 'darwin') {
					grunt.task.run('appdmg:main:mac-generic');
				}
			}
			if (griffin) {
				// do mac griffin build
				grunt.task.run('copy:main:mac-griffin');
				grunt.task.run('copy:production:mac-griffin');
				grunt.task.run('copy:griffin:mac-griffin');
				grunt.task.run('stylus:compile:mac-griffin');
				grunt.task.run('coffee:compileMultiple:mac-griffin');
				grunt.task.run('clean:coffee:mac-griffin');
				grunt.task.run('nwjs:mac:mac-griffin');
				grunt.task.run('exec:codesign:mac-griffin');
				if (process.platform == 'darwin') {
					grunt.task.run('appdmg:main:mac-griffin');
				}
			}
		}
		grunt.task.run('clean:temp');
	});
	
};
