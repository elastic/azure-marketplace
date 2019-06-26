var gulp = require("gulp");
var eclint = require("eclint");
var jsonlint = require("gulp-jsonlint");
var zip = require("gulp-zip");
var addsrc = require('gulp-add-src');
var timestamp = require("./tasks/lib/timestamp");
var transform = require('gulp-transform');
var path = require("path");
var _ = require('lodash');

require('requiredir')('tasks', { recurse: true });

_.mixin({
  indexBy: _.keyBy
});

gulp.task("default", gulp.series("sanity-checks", "patch", function() {
  var stream = gulp.src(["../src/**/*.json"])
    // update tracking guids when creating release
    .pipe(transform('utf8', function (content, file) {
      return new Promise((resolve, reject) => {
        if (path.basename(file.path) === "mainTemplate.json") {
          var allowedValues = require("./allowedValues.json");
          var mainTemplate = JSON.parse(content);
          mainTemplate.parameters.elasticTags.defaultValue.tracking = allowedValues.marketplace.trackingGuids;
          mainTemplate.parameters._artifactsLocation.defaultValue = allowedValues.marketplace._artifactsLocation;
          resolve(JSON.stringify(mainTemplate, null, 2) + "\n");
        }

        resolve(content);
      });
    }))
    .pipe(jsonlint())
    .pipe(jsonlint.reporter())
    .pipe(eclint.check({
      reporter: function(file, message) {
        console.error(file.path + ":", message);
      }
    }))
    .pipe(jsonlint.failAfterError())
    .pipe(addsrc.append(["../src/**/*.sh"]))
    .pipe(zip("elasticsearch-marketplace" + timestamp +".zip"))
    .pipe(gulp.dest("../dist/releases"))

  stream.on("finish", function() {});

  return stream;
}));

gulp.task("release", gulp.series("default", "deploy", function() {
  var stream = gulp.src(["../dist/test-runs/tmp/*.log"])
    .pipe(zip("test-results" + timestamp +".zip"))
    .pipe(gulp.dest("../dist/releases"))

  stream.on("finish", function() {});

  return stream;
}));
