var gulp = require("gulp");
var jsonfile = require('jsonfile');
var _ = require('lodash');
var replace = require('gulp-replace');

jsonfile.spaces = 2;

var mainTemplate = "../src/mainTemplate.json";
var uiTemplate = "../src/createUiDefinition.json";
var installElasticsearchBash = "../src/scripts/elasticsearch-ubuntu-install.sh";

var allowedValues = require('../allowedValues.json');
var versions = _.keys(allowedValues.versions);
var esToKibanaMapping = _.mapValues(allowedValues.versions, function(v) { return v.kibana; });
var vmSizes = allowedValues.vmSizes;
var dataNodeValues = _.range(1, allowedValues.numberOfDataNodes + 1)
  .filter(function(i) { return i <= 12 || (i % 5) == 0; })
  .map(function (i) { return { "label" : i + "", value : i }});
var clientNodeValues = _.range(1, allowedValues.numberOfClientNodes + 1)
  .filter(function(i) { return i <= 12 || (i % 5) == 0; })
  .map(function (i) { return { "label" : i + "", value : i }});

gulp.task('bash-patch', function(){
  var elifs = 0;
  var branches = _.keys(allowedValues.versions)
    .filter(function(k) { return !!allowedValues.versions[k].downloadUrl })
    .map(function (k) {
      var v = allowedValues.versions[k];
      var command = (elifs == 0) ? "if" : "elif";
      elifs++;
      return  "    " + command +" [[ \"${ES_VERSION}\" == \"" + k + "\"]]; then\r\n      DOWNLOAD_URL=\"" +v.downloadUrl+ "\"\r\n";
    });
  var ifStatements = branches.join("")

  return gulp.src([installElasticsearchBash])
    .pipe(replace(/(\#begin telemetry.*)[\s\S]+(\#end telemetry.*)/g, "$1\r\n" + ifStatements + "    $2"))
    .pipe(gulp.dest("../src/scripts/", { overwrite: true }));
});

gulp.task("patch", ['link-checker', 'bash-patch'], function(cb) {

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

        var dataNodeCountControl = _.find(nodesStep.elements, function (el) { return el.name == "vmDataNodeCount"; });
        dataNodeCountControl.constraints.allowedValues = dataNodeValues;
        var clientNodeCountControl = _.find(nodesStep.elements, function (el) { return el.name == "vmDataNodeCount"; });
        clientNodeCountControl.constraints.allowedValues = clientNodeValues;

        jsonfile.writeFile(uiTemplate, obj, function (err) {
          cb();
        });
      });
    });
  });
});
