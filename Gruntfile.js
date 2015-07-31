module.exports = function(grunt) {
grunt.initConfig({
    pkg: grunt.file.readJSON('package.json'),
	nwjs: {
        options: {
			appName: '<%= pkg.displayName %>',
			//macCredits: 'path-to-file',
			macIcns: './img/konode-icon-osx.icns',
			//winIco: './img/konode-icon-win.ico', // causes problems when run from osx
            version: '<%= pkg.dependencies.nodewebkit %>', //nwjs version to download
			platforms: ['osx64','win64'],
			buildType: 'versioned',
            buildDir: '../konote-builds',
			cacheDir: '../konote-builds/cache',
            macZip: false,
			forceDownload: true
        },
        //src: ['./app.nw']
		// similar to node globbing patterns, but ! here excludes the match rather than negates it
		src: ['./package.json', './**/*', '!./node_modules/nodewebkit/**/*', '!./node_modules/nw/**/*', '!./node_modules/grunt*/**/*', '!./README.md', '!./.git/**/*']
    }
})
	// load the nwjs builder plugin
	grunt.loadNpmTasks('grunt-nw-builder');

};
