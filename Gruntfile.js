/*
grunt task for release builds of konote

creates a 'konote-builds' folder beside the project directory containing a mac .dmg and windows .zip

as a final build step on windows, the KoNote.exe icon can be replaced with Resource Hacker:
ResHacker.exe -modify "KoNote.exe", "KoNote.exe", "icon.ico", ICONGROUP, MAINICON, 0

note: requires forked nw-builder module (disables merging win build with the nw exe)
https://github.com/speedskater/node-webkit-builder
*/

module.exports = function(grunt) {
	grunt.initConfig({
    	pkg: grunt.file.readJSON('package.json'),
		
		// downloads nwjs binaries and bundles w project
		nwjs: {
			options: {
				appName: '<%= pkg.displayName %>',
				//macCredits: 'path-to-file',
				macIcns: './icon.icns',
				version: '<%= pkg.dependencies.nodewebkit %>', //nwjs version to download
				platforms: ['osx64', 'win32'],
				buildType: 'default',
				buildDir: '../konote-builds',
				cacheDir: '../konote-builds/cache',
				macZip: false,
				winZip: false,
				forceDownload: true
			},
			// TODO: see if we can simpify these globs -- seems package.json is explicitly required
			src: ['./package.json', './**/*', '!./node_modules/nodewebkit/**/*', '!./node_modules/nw/**/*', '!./node_modules/grunt*/**/*', '!./README.md', '!./.git/**/*']
    	},
		// format the osx folder icon for the dmg, zip windows build, cleanup tmp files
		exec: {
			prep: "mv ../konote-builds/KoNote/osx64 ../konote-builds/KoNote/KoNote",
			append: "Rez -append icon.rsrc -o ../konote-builds/KoNote/KoNote/$'Icon\r'",
			set: "SetFile -a C ../konote-builds/KoNote/KoNote",
			hide: "SetFile -a V $'../konote-builds/KoNote/KoNote/Icon\r'",
			zip: {
				cwd: '../konote-builds/KoNote/win32',
				cmd: 'zip -r --quiet ../../konote-<%= pkg.version %>-w32.zip *'
			},
			clean: 'rm -rf ../konote-builds/KoNote ../konote-builds/cache'
		},
		// build pretty .dmg
		appdmg :{
			options: {
				basepath: './',
				title: 'KoNote-<%= pkg.version %>',
				icon: 'icon.icns',
				background: 'background.tiff', 'icon-size': 104,
				contents: [
					{x: 130, y: 150, type: 'file', path: '../konote-builds/KoNote/KoNote'},
					{x: 320, y: 150, type: 'link', path: '/Applications'}
				]
			},
			target: {
				dest: '../konote-builds/konote-<%= pkg.version %>-mac.dmg'
			}
		}
	});
	
	// load the plugins
	grunt.loadNpmTasks('grunt-nw-builder');
	grunt.loadNpmTasks('grunt-appdmg');
	grunt.loadNpmTasks('grunt-exec');
	
	// wooo
	grunt.registerTask('build', ['nwjs', 'exec:prep', 'exec:append', 'exec:set', 'exec:hide', 'appdmg', 'exec:zip', 'exec:clean']);

};
