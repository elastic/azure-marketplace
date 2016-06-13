var config = require('../.test.json');
var gulp = require("gulp");
const execFile = require('child_process').execFile;
var fs = require('fs');
var _ = require('lodash');
var dateFormat = require("dateformat");

var azureCli = "..\\node_modules\\.bin\\azure.cmd"; //TODO *nix
var armTests = {}
var bailOut = function (error) {
  throw error;
}

var validateTemplates = function(cb)
{
  console.log(armTests)
  var validated = 0;
  var allValidated = function()
  {
    validated++;
    if (validated == armTests.length) cb();
  };
  _.keys(armTests).forEach((t) => {
    validateTemplate(t, allValidated)
  });
}

var uri = "https://raw.githubusercontent.com/elastic/azure-marketplace/master/src/mainTemplate.json";
var validateTemplate = function(test, cb)
{
  var rg = armTests[test];
  var createGroup = [ 'group', 'create', rg, 'westeurope', '--json'];
  var validateGroup = [ 'group', 'template', 'validate',
    '--resource-group', rg,
    '--template-uri', uri,
    '--parameters-file', "arm-tests/" + test,
    '--json'
  ];
  console.log("creating resource group:" + rg);
  execFile(azureCli, createGroup, (error, stdout, stderr) => {
    if (error) throw error;
    var result = JSON.parse(stdout);
    if (result.properties.provisioningState != "Succeeded") bailOut(new Error("failed to create resourceGroup: " + rg));

    console.log("validating "+ test +" in resource group:" + rg);
    execFile(azureCli, validateGroup, (error, stdout, stderr) => {
      if (error) throw error;
      if (stderr) bailOut(new Error(stderr));
      console.log(stderr);
      var result = JSON.parse(stdout);
      console.log(result)
      cb();
    });
  });
}

gulp.task("test", function(cb) {
  var login = [ 'login', '--service-principal',
    '--username', config.arm.clientId,
    '--password', config.arm.clientSecret,
    '--tenant', config.arm.tenantId
  ];
  var child = execFile(azureCli, login, (error, stdout, stderr) => {
    if (error) throw error;
    armTests = _(fs.readdirSync("arm-tests"))
      .indexBy((f) => f)
      .mapValues(f => "test-" + f.replace(".json", "") + dateFormat(new Date(), "-yyyymmdd-HHMMssl").replace("+","-"))
      .value();
    validateTemplates();
  });
});

var deleteAllTestGroups = function (cb)
{
  var groupList = [ 'group', 'list', '--json'];
  console.log("getting a list of all resources that start with test-");
  execFile(azureCli, groupList, (error, stdout, stderr) => {
    if (error) throw error;
    if (stderr) bailOut(new Error(stderr));
    var result = JSON.parse(stdout);
    var testGroups = _(result).map(g=>g.name).filter(n=>n.match(/^test\-/)).value();
    var deleted = 0;
    var allDeleted = function()
    {
      deleted++;
      if (deleted == testGroups.length) cb();
    };
    console.log("deleting "+testGroups.length+" resource groups");
    testGroups.forEach(n=> {
      var groupDelete = [ 'group', 'delete', n, '-q', '--json', '--no'];
      console.log("deleting resource group :" + n);
      execFile(azureCli, groupDelete, (error, stdout, stderr) => {
        if (error) throw error;
        if (stderr) bailOut(new Error(stderr));
        allDeleted();
      });
    });
  });
}
gulp.task("azure-cleanup", function(cb) {
  var login = [ 'login', '--service-principal',
    '--username', config.arm.clientId,
    '--password', config.arm.clientSecret,
    '--tenant', config.arm.tenantId
  ];
  var child = execFile(azureCli, login, (error, stdout, stderr) => {
    if (error) throw error;
    deleteAllTestGroups(cb)
  });
});
