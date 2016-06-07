var gulp = require("gulp");
var eclint = require("eclint");
var jsonlint = require("gulp-jsonlint");
var zip = require("gulp-zip");
var dateFormat = require("dateformat");
var addsrc = require('gulp-add-src');

gulp.task("default", ["patch", "generate-data-nodes-resource"], function() {
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
    .pipe(zip("elasticsearch-marketplace" + dateFormat(new Date(), "-yyyymmdd-HHMMss-Z").replace("+","-") +".zip"))
    .pipe(gulp.dest("../dist/releases"))

  stream.on("finish", function() {});

  return stream;
});
