var gulp = require("gulp");
var phantomjs = require('phantomjs-prebuilt')
var casperJs = require('gulp-casperjs');
var spawn = require('child_process').spawn;
var gutil = require('gulp-util');

process.env["PHANTOMJS_EXECUTABLE"] = phantomjs.path;
console.log(process.env["PHANTOMJS_EXECUTABLE"])


gulp.task("headless", function () {
    var tests = ['../build/ui-tests/runner.js'];
    var casperChild = spawn('../node_modules/casperjs/bin/casperjs.exe', tests);

    casperChild.stderr.on('data', function (data) {
      gutil.log('CasperJS:', data.toString().slice(0, -1));
    });
    casperChild.stdout.on('data', function (data) {
      gutil.log('CasperJS:', data.toString().slice(0, -1));
    });

    casperChild.on('close', function (code) {
      var success = code === 0; // Will be 1 in the event of failure

      // Do something with success here
    });
});
