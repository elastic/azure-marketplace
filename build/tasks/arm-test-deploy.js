var config = require('../.test.json');
var gulp = require("gulp");
const execFile = require('child_process').execFile;
const spawn = require('child_process').spawn;
var fs = require('fs');
var _ = require('lodash');
var dateFormat = require("dateformat");
var git = require('git-rev')
var merge = require('merge');
var mkdirp = require('mkdirp');
var del = require('del');
var request = require('request');
var hostname = require("os").hostname();
var operatingSystem = require("os").platform();

var azureCli = "../node_modules/.bin/azure";
if (operatingSystem === "win32")
  azureCli = "..\\node_modules\\.bin\\azure.cmd";

var runDate = dateFormat(new Date(), "-yyyymmdd-HHMMss-Z").replace("+","-");
var log = (data) => console.log(data);


var bootstrapTest = (artifactsBaseUrl) =>
{
  var params = require("../../parameters/test.parameters.json");
  params.artifactsBaseUrl.value = artifactsBaseUrl;
  params.adminUsername.value = config.deployments.username;
  params.adminPassword.value = config.deployments.password;
  params.sshPublicKey.value = config.deployments.ssh;

  params.securityBootstrapPassword.value = config.deployments.securityPassword;
  params.securityAdminPassword.value = config.deployments.securityPassword;
  params.securityReadPassword.value = config.deployments.securityPassword;
  params.securityKibanaPassword.value = config.deployments.securityPassword;
  params.securityAdminPassword.value = config.deployments.securityPassword;
  params.securityLogstashPassword.value = config.deployments.securityPassword;

  return {
    location: "westeurope",
    resourceGroup: "test-" + hostname.toLowerCase() + "-" + "single" + dateFormat(new Date(), "-yyyymmdd-HHMMssl").replace("+","-"),
    templateUri:  artifactsBaseUrl + "/mainTemplate.json",
    params: params
  }
}

var bootstrap = (cb) => {
  git.branch(function (branch) {
    var artifactsBaseUrl = "https://raw.githubusercontent.com/elastic/azure-marketplace/"+ branch + "/src";
    var test = bootstrapTest(artifactsBaseUrl);
    cb(test);
  })
};

var login = (cb) => bootstrap((test) => {
  var login = [ 'login', '--service-principal',
    '--username', config.arm.clientId,
    '--password', config.arm.clientSecret,
    '--tenant', config.arm.tenantId
  ];
  log("logging into azure cli tooling")
  var child = execFile(azureCli, login, (error, stdout, stderr) => {
    if (error || stderr) return bailOut(error || new Error(stderr), true);
    cb(test);
  });
});

var logout = (cb) => {
  var logout = [ 'logout', config.arm.clientId];
  log("logging out of azure cli tooling")
  execFile(azureCli, logout, cb);
}

var bailOut = (error)  => {
  if (!error) return;
  log(error);
  logout(() => { throw error; });
}

var createResourceGroup = (test, cb) => {
  var rg = test.resourceGroup;
  var location = test.location;
  var createGroup = [ 'group', 'create', rg, location, '--json'];
  log("creating resource group: " + rg);
  execFile(azureCli, createGroup, (error, stdout, stderr) => {
    if (error || stderr) return bailOut(error || new Error(stderr));

    if (!stdout) return bailOut(new Error("No output returned when creating resourceGroup: " + rg));

    log("createGroupResult: " + stdout);
    var result = JSON.parse(stdout);
    if (result.properties.provisioningState != "Succeeded") return bailOut(new Error("failed to create resourceGroup: " + rg));
    cb();
  });
}

var validateTemplate = (test, cb) => {
  var p = JSON.stringify(test.params)
  var rg = test.resourceGroup;
  createResourceGroup(test, () => {
    var validateGroup = [ 'group', 'template', 'validate',
      '--resource-group', rg,
      '--template-uri', test.templateUri,
      '--parameters', p,
      '--json'
    ];
    log("validating resource group: " + rg);
    execFile(azureCli, validateGroup, (error, stdout, stderr) => {
      log("validation errors:" + (error || stderr));
      if ((error || stderr)) return bailOut(error || new Error(stderr));
      cb(test);
    });
  })
}
var showOperationList = (test, cb) => {
  var rg = test.resourceGroup;
  var operationList = [ 'group', 'deployment', 'operation', 'list',
    rg,
    'mainTemplate',
    '--json'
  ];
  log("getting operation list result for deployment in resource group: " + rg);
  execFile(azureCli, operationList, (error, stdout, stderr) => {
    log("operationListResult:" + !!(stdout || stderr));
    if (error || stderr) return bailOut(error || new Error(stderr));
    var result = JSON.parse(stdout)
    var errors = _(result)
      .filter(f=>f.properties.provisioningState !== "Succeeded")
      .map(f=>f.properties.statusMessage)
      .value();
    errors.forEach(e => {
      log("resulted in error: " + JSON.stringify(e, null, 2));
    })
    console.error("deploment failed!")
    cb();
  });
}

var deployTemplate = (test, cb) => {
  var p = JSON.stringify(test.params)
  var rg = test.resourceGroup;
  var deployGroup = [ 'group', 'deployment', 'create',
    '--resource-group', rg,
    '--template-uri', test.templateUri,
    '--parameters', p,
    '--quiet',
    '--json'
  ];
  log("deploying in resource group: " + rg);
  execFile(azureCli, deployGroup, (error, stdout, stderr) => {
    log("deployResult: " + !!(stdout || stderr));
    if (error || stderr) showOperationList(test, ()=> bailOut(error || new Error(stderr)));
    else {
      log("Success! outputs: " + JSON.stringify(JSON.parse(stdout, null, 2).properties.outputs, null, 2))
    }
  });
}

gulp.task("deploy-test", function(cb) {
  login((test) => validateTemplate(test, (test) => deployTemplate(test, () => logout(cb))));
});
