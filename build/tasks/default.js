var gulp = require("gulp");
var eclint = require("eclint");
var jsonlint = require("gulp-jsonlint");
var zip = require("gulp-zip");
var addsrc = require('gulp-add-src');
var timestamp = require("./lib/timestamp");

gulp.task("default", ["sanity-checks", "patch"], function() {
  var stream = gulp.src(["../src/**/*.json"])
    .pipe(jsonlint())
    .pipe(jsonlint.reporter())
    .pipe(eclint.check({
      reporter: function(file, message) {
        //var relativePath = path.relative(".", file.path);
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

gulp.task("release", ["default", "deploy-all"], function() {
  var stream = gulp.src(["../dist/test-runs/tmp/*.log"])
    .pipe(zip("test-results" + timestamp +".zip"))
    .pipe(gulp.dest("../dist/releases"))

  stream.on("finish", function() {});

  return stream;
});
