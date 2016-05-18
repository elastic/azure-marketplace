var gulp = require("gulp");
var phantomjs = require('phantomjs-prebuilt')
var casperJs = require('gulp-casperjs');
var spawn = require('child_process').spawn;
var gutil = require('gulp-util');

process.env["PHANTOMJS_EXECUTABLE"] = phantomjs.path;

gulp.task("headless", function () {
    try {
      stats = fs.statSync("../build/ui-tests/ui-tests-config.json");
    }
    catch (e) {
      console.error("In order to run headless tests copy ui-tests-config.example.json => ui-tests-config.json in 'build/ui-tests'");
      process.exit(1)
    }
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
