var gulp = require("gulp");
var jsonfile = require('jsonfile');
var _ = require('lodash');

jsonfile.spaces = 2;

var mainTemplate = "../src/mainTemplate.json";
var uiTemplate = "../src/createUiDefinition.json";
var nodeResources = "../src/partials/node-resources.json";

var allowedValues = require('../allowedValues.json');
var versions = allowedValues.versions;

var vmSizes = _.map(allowedValues.vmSizes, function(v) { return v[0]; });
var kibanaVmSizes = _.difference(vmSizes, allowedValues.ignoredKibanaVmsBecauseNotEnoughRam);

var recommendedSizes = _(allowedValues.vmSizes)
  .filter(function(v) { return v[3] })
  .map(function(v) { return v[0]; });

var dataNodeValues = _.range(1, allowedValues.numberOfDataNodes + 1)
  .filter(function(i) { return i <= 12 || (i % 5) == 0; })
  .map(function (i) { return { "label" : i + "", value : i }});

var clientNodeValues = _.range(0, allowedValues.numberOfClientNodes + 1)
  .filter(function(i) { return i <= 12 || (i % 5) == 0; })
  .map(function (i) { return { "label" : i + "", value : i }});

var recommendedMinClusterVmSize = "Standard_DS1_v2";
var recommendedKibanaSizes = ["Standard_A2_v2", "Standard_A4_v2", "Standard_A8_v2"];
var recommendedMinKibanaVmSize = recommendedKibanaSizes[0];

gulp.task("patch", function(cb) {

  jsonfile.readFile(nodeResources, function(err, resources) {

    resources.variables.locations = allowedValues.locations;
    resources.variables.vmAcceleratedNetworking = allowedValues.vmAcceleratedNetworking;

    jsonfile.writeFile(nodeResources, resources, function(err) {

      jsonfile.readFile(mainTemplate, function(err, main) {
        var diskSizes = allowedValues.diskSizes;

        main.variables.dataSkuSettings = _(_.map(allowedValues.vmSizes, function(v) {
          return {
            tier: v[0],
            dataDisks: v[1],
            storageAccountType: v[2] + "_LRS"
          }
        })).indexBy(function (v) {
          var tier = v.tier;
          delete v.tier;
          return tier;
        });

        main.parameters.esVersion.allowedValues = versions;
        main.parameters.esVersion.defaultValue = _.last(versions);
        main.parameters.vmSizeDataNodes.allowedValues = vmSizes;
        main.parameters.vmSizeDataNodes.defaultValue = recommendedMinClusterVmSize;
        main.parameters.vmDataDiskCount.defaultValue = _(allowedValues.vmSizes).map((vm) => vm[1]).max();
        main.parameters.vmDataDiskSize.allowedValues = diskSizes;
        main.parameters.vmDataDiskSize.defaultValue = allowedValues.defaultDiskSize;
        main.parameters.vmSizeMasterNodes.allowedValues = vmSizes;
        main.parameters.vmSizeMasterNodes.defaultValue = recommendedMinClusterVmSize;
        main.parameters.vmSizeClientNodes.allowedValues = vmSizes;
        main.parameters.vmSizeClientNodes.defaultValue = recommendedMinClusterVmSize;
        main.parameters.vmSizeKibana.allowedValues = kibanaVmSizes;
        main.parameters.vmSizeKibana.defaultValue = recommendedMinKibanaVmSize;
        main.parameters.vmSizeLogstash.allowedValues = vmSizes;
        main.parameters.vmSizeLogstash.defaultValue = recommendedMinClusterVmSize;

        jsonfile.writeFile(mainTemplate, main, function (err) {
          jsonfile.readFile(uiTemplate, function(err, ui) {

            //patch allowed versions on the cluster step
            var clusterStep = _.find(ui.parameters.steps, function (step) {
              return step.name == "clusterSettingsStep";
            });
            var versionControl = _.find(clusterStep.elements, function (el) {
              return el.name == "esVersion";
            });
            versionControl.constraints.allowedValues = _.map(versions, function(v) {
              return { label: "v" + v, value : v };
            });
            versionControl.defaultValue = "v" + _.last(versions);

            //patch allowedVMSizes on the nodesStep
            var nodesStep = _.find(ui.parameters.steps, function (step) { return step.name == "nodesStep"; });
            var dataNodesSection = _.find(nodesStep.elements, function (el) { return el.name == "dataNodes"; });
            var masterNodesSection = _.find(nodesStep.elements, function (el) { return el.name == "masterNodes"; });
            var clientNodesSection = _.find(nodesStep.elements, function (el) { return el.name == "clientNodes"; });
            var externalAccessStep = _.find(ui.parameters.steps, function (step) { return step.name == "externalAccessStep"; });
            var masterSizeControl = _.find(masterNodesSection.elements, function (el) { return el.name == "vmSizeMasterNodes"; });
            var dataSizeControl = _.find(dataNodesSection.elements, function (el) { return el.name == "vmSizeDataNodes"; });
            var clientSizeControl = _.find(clientNodesSection.elements, function (el) { return el.name == "vmSizeClientNodes"; });

            var kibanaSection = _.find(externalAccessStep.elements, function (el) { return el.name == "kibanaSection"; });
            var kibanaSizeControl = _.find(kibanaSection.elements, function (el) { return el.name == "vmSizeKibana"; });

            var logstashSection = _.find(externalAccessStep.elements, function (el) { return el.name == "logstashSection"; });
            var logstashSizeControl = _.find(logstashSection.elements, function (el) { return el.name == "vmSizeLogstash"; });

            var patchVmSizes = function(control, allowedSizes, recommendedSizes, recommendedSize) {
              delete control.constraints.allowedSizes;
              control.constraints.allowedSizes = allowedSizes;
              var sizes = recommendedSizes.slice();
              var fromIndex = sizes.indexOf(recommendedSize);
              if (fromIndex == -1) {
                throw new Error(`recommendSize '${recommendedSize}' not found in recommendedSizes ${recommendedSizes}`);
              }
              sizes.splice(fromIndex, 1);
              sizes.unshift(recommendedSize);
              control.recommendedSizes = sizes;
            }
            patchVmSizes(masterSizeControl, vmSizes, recommendedSizes, recommendedMinClusterVmSize);
            patchVmSizes(dataSizeControl, vmSizes, recommendedSizes, recommendedMinClusterVmSize);
            patchVmSizes(clientSizeControl, vmSizes, recommendedSizes, recommendedMinClusterVmSize);
            patchVmSizes(kibanaSizeControl, kibanaVmSizes, recommendedKibanaSizes, recommendedMinKibanaVmSize);
            patchVmSizes(logstashSizeControl, vmSizes, recommendedSizes, recommendedMinClusterVmSize);

            var dataNodeCountControl = _.find(dataNodesSection.elements, function (el) { return el.name == "vmDataNodeCount"; });
            dataNodeCountControl.constraints.allowedValues = dataNodeValues;
            var clientNodeCountControl = _.find(clientNodesSection.elements, function (el) { return el.name == "vmClientNodeCount"; });
            clientNodeCountControl.constraints.allowedValues = clientNodeValues;

            var dataNodesDisksSection = _.find(nodesStep.elements, function (el) { return el.name == "dataNodesDisks"; });
            var dataDisksControl = _.find(dataNodesDisksSection.elements, function (el) { return el.name == "vmDataDiskSize"; });

            dataDisksControl.constraints.allowedValues = _.map(diskSizes, function(d) {
              return { label: d, value : d };
            });
            dataDisksControl.defaultValue = allowedValues.defaultDiskSize;;

            jsonfile.writeFile(uiTemplate, ui, function (err) {
              cb();
            });
          });
        });
      });

    });
  });
});
