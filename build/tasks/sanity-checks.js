var gulp = require("gulp");
var _ = require('lodash');
var filereader = require('./lib/filereader');

function checks(cb) {
  var errors = [];
  var mainTemplate = require("../../src/mainTemplate.json");
  var mainTemplateParams = _.keys(mainTemplate.parameters);

  var marketPlaceArmParity = () => {
    var uiTemplate = require("../../src/createUiDefinition.json");
    var difference = _.difference(mainTemplateParams, _.keys(uiTemplate.parameters.outputs));
    if (difference.length == 0) return;
    var excludingDefault = [];
    difference.forEach(p=> {
      if (mainTemplate.parameters[p] && mainTemplate.parameters[p].defaultValue) return;
      excludingDefault.push(p);
    });
    if (excludingDefault.length == 0) return;
    errors.push("Main template has different inputs as the ui template outputs: " + excludingDefault)
  }

  var outputDiff = (kind, template, empty) => {
    var template = require("../../src/" + template);
    var empty = require("../../src/" + empty)
    var difference = _.difference(_.keys(template.outputs), _.keys(empty.outputs));
    if (difference.length == 0) return;
    errors.push("The " + kind +" template differs from its empty variant: " + difference);
  }

  var parametersParity = () => {
    var parameters = [
      {
        name: "password",
        template: require("../../parameters/password.parameters.json")
      },
      {
        name: "ssh",
        template: require("../../parameters/ssh.parameters.json")
      }];

    parameters.forEach(p=> {
      var difference = _.difference(mainTemplateParams, _.keys(p.template));
      if (difference.length == 0) return;
      var excludingDefault = [];
      difference.forEach(p=> {
        if (mainTemplate.parameters[p] && mainTemplate.parameters[p].defaultValue) return;
        excludingDefault.push(p);
      });
      if (excludingDefault.length == 0) return;
      errors.push(p.name + " parameters has different inputs than the main template parameters: " + excludingDefault)
    });
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
  parametersParity();

  filereader.readFiles('../src/', filter, resourcesHaveProviderTag);

  if (errors.length) {
    throw new Error("Sanity checks failed:\n" + errors.join('\n'));
  }

  cb();
}

gulp.task("sanity-checks", checks);
