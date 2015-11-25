var gulp = require("gulp");
var eclint = require("eclint");
var jsonlint = require("gulp-jsonlint");
var zip = require("gulp-zip");
var dateFormat = require("dateformat");
var jsonfile = require('jsonfile');
var _ = require('lodash');

jsonfile.spaces = 2;

gulp.task("patch", function(cb) {
  jsonfile.readFile("../src/allowedValues.json", function(err, obj) {
    var versions = obj.versions;
    var vmSizes = obj.vmSizes;

    var mainTemplate = "../src/mainTemplate.json";
    var uiTemplate = "../src/createUiDefinition.json";

    jsonfile.readFile(mainTemplate, function(err, obj) {
      obj.parameters.esVersion.allowedValues = versions;
      obj.parameters.vmSizeDataNodes.allowedValues = vmSizes;
      obj.parameters.vmSizeMasterNodes.allowedValues = vmSizes;
      obj.parameters.vmSizeClientNodes.allowedValues = vmSizes;
      jsonfile.writeFile(mainTemplate, obj, function (err) {
        jsonfile.readFile(uiTemplate, function(err, obj) {
          var clusterStep = _.find(obj.parameters.steps, function (step) {
            return step.name == "clusterSettingsStep";
          });
          var versionControl = _.find(clusterStep.elements, function (el) {
            return el.name == "esVersion";
          });
          versionControl.constraints.allowedValues = _.map(versions, function(v)
          {
            return { label: "v" + v, value : v};
          });
          jsonfile.writeFile(uiTemplate, obj, function (err) {
            cb();
          });
        });
      });
    });
  });
});


gulp.task("default", ["patch"], function() {
    var stream = gulp.src([
            "../src/**/*.json"
        ])
        .pipe(jsonlint())
        .pipe(jsonlint.reporter())
        .pipe(eclint.check({
            reporter: function(file, message) {
                //var relativePath = path.relative(".", file.path);
                console.error(file.path + ":", message);
            }
        }))
        .pipe(jsonlint.failAfterError())
        .pipe(zip("elasticsearch-marketplace" + dateFormat(new Date(), "-yyyymmdd-hhMMss-Z").replace("+","-") +".zip"))
        .pipe(gulp.dest("../dist"));
        ;
    stream.on("finish", function() {
    });
    return stream;
});
