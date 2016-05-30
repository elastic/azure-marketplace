var gulp = require("gulp");
var jsonfile = require('jsonfile');
var _ = require('lodash');
var replace = require('gulp-replace');

jsonfile.spaces = 2;

var mainTemplate = "../src/mainTemplate.json";
var uiTemplate = "../src/createUiDefinition.json";

var allowedValues = require('../allowedValues.json');
var versions = _.keys(allowedValues.versions);
var esToKibanaMapping = _.mapValues(allowedValues.versions, function(v) { return v.kibana; });

var vmSizes = _.map(allowedValues.vmSizes, function(v) { return v[0]; });
var recommendedSizes = _(allowedValues.vmSizes)
  .filter(function(v) { return v[3] })
  .map(function(v) { return v[0]; });

var dataNodeValues = _.range(1, allowedValues.numberOfDataNodes + 1)
  .filter(function(i) { return i <= 12 || (i % 5) == 0; })
  .map(function (i) { return { "label" : i + "", value : i }});

var clientNodeValues = _.range(1, allowedValues.numberOfClientNodes + 1)
  .filter(function(i) { return i <= 12 || (i % 5) == 0; })
  .map(function (i) { return { "label" : i + "", value : i }});

//generate binPackMap of max data nodes but leave a minimum of 60 intact because thats what we shipped the ARM template with
var binPackMap = _.range(1, Math.max(61, Math.max(allowedValues.numberOfDataNodes, allowedValues.numberOfClientNodes) + 1))
  .map(function (i) { return "[div(sub(add(" + i + ", variables('nodesPerStorageAccount')), 1), variables('nodesPerStorageAccount'))]" });

var allowedLocations = _(["ResourceGroup"]).concat(allowedValues.locations)

gulp.task("patch", function(cb) {

  jsonfile.readFile(mainTemplate, function(err, obj) {
    obj.variables.dataSkuSettings = _(_.map(allowedValues.vmSizes, function(v) {
      // 16 => 2
      // 8 => 4
      // 4 => 6
      // 2 => 8
      // 1 => 10
      var nodesPerStorageAccount = Math.max(1, (10 - ((Math.log(v[1]) / Math.log(2)) * 2)));
      return {
        tier: v[0],
        dataDisks: v[1],
        nodesPerStorageAccount: nodesPerStorageAccount,
        storageAccountType: v[2] + "_LRS"
      }
    })).indexBy(function (v) {
      var tier = v.tier;
      delete v.tier;
      return tier;
    });

    obj.variables.storageBinPackMap = binPackMap;
    obj.variables.esToKibanaMapping = esToKibanaMapping;

    obj.parameters.location.allowedValues = allowedLocations;
    obj.variables.locationMap = _(allowedLocations)
      .indexBy(function(location) { return location; })
      .mapValues(function(k) { return (k === "ResourceGroup") ? "[resourceGroup().location]" : "[resourceGroup().location]"; });

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
        var patchVmSizes = function(control, patchRecommended) {
          delete control.constraints.allowedValues;
          control.constraints.allowedSizes = vmSizes;
          if (patchRecommended)
          {
            control.recommendedSizes = recommendedSizes;
            control.defaultValue = _(recommendedSizes).first();
          }
        }
        patchVmSizes(masterSizeControl);
        patchVmSizes(dataSizeControl, true);
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
