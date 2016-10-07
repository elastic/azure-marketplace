var gulp = require("gulp");
var _ = require('lodash');
var errors = [];

var marketPlaceArmParity = () => {
  var mainTemplate = require("../../src/mainTemplate.json");
  var uiTemplate = require("../../src/createUiDefinition.json");
  var mainTemplateParams = _.keys(mainTemplate.parameters);
  var difference = _.difference(mainTemplateParams, _.keys(uiTemplate.parameters.outputs));
  if (difference.length == 0) return;
  var excludingDefault = [];
  difference.forEach(p=> {
    if (mainTemplate.parameters[p] && mainTemplate.parameters[p].defaultValue) return;
    excludingDefault.push(p);
  })
  if (excludingDefault.length == 0) return;
  errors.push("Main template has different inputs as the ui template outputs" + excludingDefault)
}


var outputDiff = (kind, template, empty) => {
  var template = require("../../src/" + template);
  var empty = require("../../src/" + empty)
  var difference = _.difference(_.keys(template.outputs), _.keys(empty.outputs));
  if (difference.length == 0) return;
  errors.push("The " + kind +" template differs from its empty variant: " + difference)
}

gulp.task("sanity-checks", function(cb) {
  marketPlaceArmParity();
  outputDiff("kibana", "machines/kibana-resources.json", "empty/empty-kibana-resources.json");
  outputDiff("jumpbox", "machines/jumpbox-resources.json", "empty/empty-jumpbox-resources.json");
  outputDiff("client", "machines/client-nodes-resources.json", "empty/empty-client-nodes-resources.json");
  outputDiff("master", "machines/master-nodes-resources.json", "empty/empty-master-nodes-resources.json");
  outputDiff("networks", "networks/existing-virtual-network.json", "networks/new-virtual-network.json");
  outputDiff("storageAccounts", "storageAccounts/existing-storage-account.json", "storageAccounts/new-storage-account.json");
  if (errors.length) throw new Error("Sanity checks failed:\n" + errors);
  cb();
});
