var gulp = require("gulp");
var eclint = require("eclint");
var jsonlint = require("gulp-jsonlint");
var zip = require("gulp-zip");
var addsrc = require('gulp-add-src');
var timestamp = require("./lib/timestamp");
var transform = require('gulp-transform');
var path = require("path");

gulp.task("default", ["sanity-checks", "patch"], function() {
  var stream = gulp.src(["../src/**/*.json"])
    .pipe(transform('utf8', function (content, file) {
      return new Promise((resolve, reject) => {
        if (path.basename(file.path) === "mainTemplate.json") {
          var allowedValues = require("../allowedValues.json");
          var mainTemplate = JSON.parse(content);
          mainTemplate.parameters.elasticTags.defaultValue.tracking = allowedValues.trackingGuids.marketplace;
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
});

gulp.task("release", ["default", "deploy"], function() {
  var stream = gulp.src(["../dist/test-runs/tmp/*.log"])
    .pipe(zip("test-results" + timestamp +".zip"))
    .pipe(gulp.dest("../dist/releases"))

  stream.on("finish", function() {});

  return stream;
});
