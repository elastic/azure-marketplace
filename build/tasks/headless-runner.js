var gulp = require("gulp");
var phantomjs = require('phantomjs-prebuilt')
var spawn = require('child_process').spawn;
var gutil = require('gulp-util');
var fs = require('fs');

process.env["PHANTOMJS_EXECUTABLE"] = phantomjs.path;

gulp.task("headless", function (cb) {
  try {
    stats = fs.statSync("../build/ui-tests/ui-tests-config.json");
  }
  catch (e) {
    console.error("In order to run headless tests copy ui-tests-config.example.json => ui-tests-config.json in 'build/ui-tests'", e);
    process.exit(1)
  }
  var runner = '../build/ui-tests/runner.js'
  var tests = [runner, '--fail-fast'];
  var casperChild = spawn('../node_modules/casperjs/bin/casperjs', ["test"].concat(tests));
  var seenError = false;
  casperChild.stderr.on('data', function (data) {
    gutil.log(data.toString().slice(0, -1));
    seenError = true;
  });
  casperChild.stdout.on('data', function (data) {
    gutil.log(data.toString().slice(0, -1));
  });

  casperChild.on('close', function (code) {
    var success = code == 0;
    if (success && !seenError)
    {
      cb();
      return;
    }
    cb(new gutil.PluginError('test', "casperjs finished with exit code " + code + " or we saw std error output: " + seenError, {showStack: false}));
  })
});
