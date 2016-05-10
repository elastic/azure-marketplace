var gulp = require("gulp");
var eclint = require("eclint");
var jsonlint = require("gulp-jsonlint");
var zip = require("gulp-zip");
var dateFormat = require("dateformat");
var jsonfile = require('jsonfile');
var _ = require('lodash');
var addsrc = require('gulp-add-src');

var phantomjs = require('phantomjs-prebuilt')
var casperJs = require('gulp-casperjs');

jsonfile.spaces = 2;
process.env["PHANTOMJS_EXECUTABLE"] = phantomjs.path;
console.log(process.env["PHANTOMJS_EXECUTABLE"])

gulp.task("patch", function(cb) {
  jsonfile.readFile("../src/allowedValues.json", function(err, obj) {
    var versions = _.keys(obj.versions);
    var esToKibanaMapping = _.mapValues(obj.versions, function(v) {
      return v.kibana;
    });
    var vmSizes = obj.vmSizes;

    var mainTemplate = "../src/mainTemplate.json";
    var uiTemplate = "../src/createUiDefinition.json";

    jsonfile.readFile(mainTemplate, function(err, obj) {

      var dataSkus = _.keys(obj.variables.dataSkuSettings);
      var difference = _.difference(vmSizes, dataSkus);

      if (difference.length > 0) {
        console.error("Not all vm sizes are property mapped as dataSku's: [" + difference.join(",") + "]");
        process.exit(1);
      }

      obj.variables.esToKibanaMapping = esToKibanaMapping;
      obj.parameters.esVersion.allowedValues = versions;
      obj.parameters.esVersion.defaultValue = _.last(versions);
      obj.parameters.vmSizeDataNodes.allowedValues = vmSizes;
      obj.parameters.vmSizeMasterNodes.allowedValues = vmSizes;
      obj.parameters.vmSizeClientNodes.allowedValues = vmSizes;
      obj.parameters.vmSizeKibana.allowedValues = vmSizes;
      jsonfile.writeFile(mainTemplate, obj, function (err) {
        jsonfile.readFile(uiTemplate, function(err, obj) {

          //patch allowed versions on the cluster step
          var clusterStep = _.find(obj.parameters.steps, function (step) {
            return step.name == "clusterSettingsStep";
          });
          var versionControl = _.find(clusterStep.elements, function (el) {
            return el.name == "esVersion";
          });
          versionControl.constraints.allowedValues = _.map(versions, function(v) {
            return { label: "v" + v, value : v};
          });
          versionControl.defaultValue = "v" + _.last(versions);

          //patch allowedVMSizes on the nodesStep
          var nodesStep = _.find(obj.parameters.steps, function (step) { return step.name == "nodesStep"; });
          var externalAccessStep = _.find(obj.parameters.steps, function (step) { return step.name == "externalAccessStep"; });

          var masterSizeControl = _.find(nodesStep.elements, function (el) { return el.name == "vmSizeMasterNodes"; });
          var dataSizeControl = _.find(nodesStep.elements, function (el) { return el.name == "vmSizeDataNodes"; });
          var clientSizeControl = _.find(nodesStep.elements, function (el) { return el.name == "vmSizeClientNodes"; });
          var kibanaSizeControl = _.find(externalAccessStep.elements, function (el) { return el.name == "vmSizeKibana"; });
          var patchVmSizes = function(control) { control.constraints.allowedValues = vmSizes; }
          patchVmSizes(masterSizeControl);
          patchVmSizes(dataSizeControl);
          patchVmSizes(clientSizeControl);
          patchVmSizes(kibanaSizeControl);

          jsonfile.writeFile(uiTemplate, obj, function (err) {
            cb();
          });
        });
      });
    });
  });
});

var spawn = require('child_process').spawn;
var gutil = require('gulp-util');

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
        .pipe(addsrc.append(["../src/**/*.sh"]))
        .pipe(zip("elasticsearch-marketplace" + dateFormat(new Date(), "-yyyymmdd-HHMMss-Z").replace("+","-") +".zip"))
        .pipe(gulp.dest("../dist"));
        ;
    stream.on("finish", function() {
    });
    return stream;
});
