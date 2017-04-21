var gulp = require("gulp");
var _ = require('lodash');
var filereader = require('./lib/filereader');

function checks(cb) {
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
    });
    if (excludingDefault.length == 0) return;
    errors.push("Main template has different inputs as the ui template outputs" + excludingDefault)
  }

  var outputDiff = (kind, template, empty) => {
    var template = require("../../src/" + template);
    var empty = require("../../src/" + empty)
    var difference = _.difference(_.keys(template.outputs), _.keys(empty.outputs));
    if (difference.length == 0) return;
    errors.push("The " + kind +" template differs from its empty variant: " + difference);
  }

  var filter = function(filename) {
    return filename.endsWith(".json");
  }

  function resourcesHaveProviderTag(filename, content) {
    var template = JSON.parse(content);
    if (template.resources) {
      template.resources.forEach(r => {
        if (r.type !== "Microsoft.Resources/deployments") {
            if (r.tags == undefined) {
              errors.push("The resource '" + r.name + "' in template '" + filename + "' does not have tags");
            }
            else if (r.tags.provider == undefined) {
              errors.push("The resource '" + r.name + "' in template '" + filename + "' is missing provider in tags");
            }
        }
        else {
          if (r.properties.parameters.elasticTags == undefined) {
            errors.push("The resource '" + r.name + "' in template '" + filename + "' does not have an elasticTags parameter");
          }
        }
      });
    }
  }

  marketPlaceArmParity();
  outputDiff("kibana", "machines/kibana-resources.json", "empty/empty-kibana-resources.json");
  outputDiff("jumpbox", "machines/jumpbox-resources.json", "empty/empty-jumpbox-resources.json");
  outputDiff("client", "machines/client-nodes-resources.json", "empty/empty-client-nodes-resources.json");
  outputDiff("master", "machines/master-nodes-resources.json", "empty/empty-master-nodes-resources.json");
  outputDiff("networks", "networks/existing-virtual-network.json", "networks/new-virtual-network.json");

  filereader.readFiles('../src/', filter, resourcesHaveProviderTag);

  if (errors.length) {
    throw new Error("Sanity checks failed:\n" + errors);
  }

  cb();
}

gulp.task("sanity-checks", checks);
