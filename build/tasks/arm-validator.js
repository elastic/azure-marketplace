var config = require('../.test.json');
var gulp = require("gulp");
const execFile = require('child_process').execFile;
var fs = require('fs');
var _ = require('lodash');
var dateFormat = require("dateformat");
var git = require('git-rev')
var merge = require('merge');
var mkdirp = require('mkdirp')
var del = require('del')

var azureCli = "..\\node_modules\\.bin\\azure.cmd"; //TODO *nix
var artifactsBaseUrl = "";
var templateUri = "";
var armTests = {};

var runDate = dateFormat(new Date(), "-yyyymmdd-HHMMss-Z").replace("+","-");
var logDist = "../dist/test-runs";
var logDistTmp = logDist + "/tmp";
var log = (f, data) =>
{
  if (!data || data === true)
  {
    var logToConsole = !data;
    data = f;
    f = "test-run"
    if (logToConsole) console.log(data);
  }
  if (!data) return;
  var file = f + ".log";
  fs.appendFileSync(logDistTmp + "/" + file, data + "\n")
}

var exampleParameters = require("../../parameters/password.parameters.json");

var bootstrapTest = (t, defaultVersion) =>
{
  var test = require("../arm-tests/" + t);
  log(t, "parameters:" + JSON.stringify(test.parameters, null, 2));
  var testParameters = merge.recursive(true, exampleParameters, test.parameters);
  testParameters.artifactsBaseUrl.value = artifactsBaseUrl;
  testParameters.adminUsername.value = config.deployments.username;
  testParameters.adminPassword.value = config.deployments.password;
  testParameters.shieldAdminPassword.value = config.deployments.shieldPassword;
  testParameters.shieldReadPassword.value = config.deployments.shieldPassword;
  testParameters.shieldKibanaPassword.value = config.deployments.shieldPassword;
  testParameters.sshPublicKey.value = config.deployments.ssh;
  testParameters.esVersion.value = defaultVersion;

  return {
    resourceGroup: "test-" + t.replace(".json", "") + dateFormat(new Date(), "-yyyymmdd-HHMMssl").replace("+","-"),
    location: test.location,
    isValid: test.isValid,
    params: testParameters
  }
}

var bootstrap = (cb) => {
  var allowedValues = require('../allowedValues.json');
  var versions = _.keys(allowedValues.versions);
  var defaultVersion = _.last(versions);
  git.branch(function (branch) {
    artifactsBaseUrl = "https://raw.githubusercontent.com/elastic/azure-marketplace/"+ branch + "/src/";
    templateUri = artifactsBaseUrl + "/mainTemplate.json";
    log("Using template: " + templateUri, false);
    armTests = _(fs.readdirSync("arm-tests"))
      .indexBy((f) => f)
      .mapValues(t => bootstrapTest(t, defaultVersion))
      .value();
    cb();
  })
};


var login = (cb) => bootstrap(() => {
  var login = [ 'login', '--service-principal',
    '--username', config.arm.clientId,
    '--password', config.arm.clientSecret,
    '--tenant', config.arm.tenantId
  ];
  log("logging into azure cli tooling")
  var child = execFile(azureCli, login, (error, stdout, stderr) => {
    if (error || stderr) return bailOut(error || new Error(stderr));
    cb();
  });
});

var logout = (cb) => {
  var logout = [ 'logout', config.arm.clientId];
  log("logging out of the  azure cli tooling")
  execFile(azureCli, logout, cb);
}

var bailOut = (error)  => {
  if (!error) return;
  log(error)
  var cb = () => logout(() => { throw error; })

  var groups = _.valuesIn(armTests).map(a=>a.resourceGroup);
  if (groups.length > 0) deleteGroups(groups, cb);
  else cb();
}

var deleteGroups = function (groups, cb) {
  var deleted = 0;
  var allDeleted = () => { if (++deleted == groups.length) cb(); };
  log("deleting "+groups.length+" resource groups");
  if (groups.length == 0) cb();
  else groups.forEach(n=> {
    var groupDelete = [ 'group', 'delete', n, '-q', '--json', '--nowait'];
    log("deleting resource group: " + n);
    execFile(azureCli, groupDelete, (error, stdout, stderr) => {
      if (error || stderr) return bailOut(error || new Error(stderr));
      log("deleted resource group: " + n, false);
      allDeleted();
    });
  });
}

var deleteAllTestGroups = function (cb) {
  var groupList = [ 'group', 'list', '--json'];
  log("getting a list of all resources that start with test-");
  execFile(azureCli, groupList, (error, stdout, stderr) => {
    if (error || stderr) return bailOut(error || new Error(stderr));
    var result = JSON.parse(stdout);
    var testGroups = _(result).map(g=>g.name).filter(n=>n.match(/^test\-/)).value();
    log("found lingering resource groups: " + testGroups, false);
    deleteGroups(testGroups, cb);
  });
}

var deleteCurrentTestGroups = function(cb)
{
  var groups = _.valuesIn(armTests).map(a=>a.resourceGroup);
  log("deleting current run groups: " + groups, true);
  deleteGroups(groups, cb);
}

var createResourceGroup = (test, cb) => {
  var rg = armTests[test].resourceGroup;
  var location = armTests[test].location;
  var createGroup = [ 'group', 'create', rg, location, '--json'];
  log("creating resource group: " + rg);
  execFile(azureCli, createGroup, (error, stdout, stderr) => {
    if (error || stderr) return bailOut(error || new Error(stderr));
    log(test, stdout);
    var result = JSON.parse(stdout);
    if (result.properties.provisioningState != "Succeeded") return bailOut(new Error("failed to create resourceGroup: " + rg));
    cb();
  });
}

var validateTemplates = function(cb) {
  var validated = 0;
  var groups = _.valuesIn(armTests).map(a=>a.resourceGroup);
  var allValidated = () => {
    if (++validated == groups.length)
    {
      log("all " + groups.length + " arm test scenarios validated");
      cb();
    }
  };
  log("start validating " + groups.length + " arm test scenarios");
  _.keys(armTests).forEach((t) => {
    validateTemplate(t, allValidated)
  });
}

var validateTemplate = (test, cb) => {
  var t = armTests[test];
  var p = JSON.stringify(t.params)
  var rg = t.resourceGroup;
  createResourceGroup(test, () => {
    var validateGroup = [ 'group', 'template', 'validate',
      '--resource-group', rg,
      '--template-uri', templateUri,
      '--parameters', p,
      '--json'
    ];
    log("validating "+ test +" in resource group: " + rg);
    execFile(azureCli, validateGroup, (error, stdout, stderr) => {
      log(test, "Expected result: " + t.isValid);
      log(test, "validateResult:" + (stdout || stderr));
      if (t.isValid && (error || stderr)) return bailOut(error || new Error(stderr));
      else if (!t.isValid && !(error || stderr)) return bailOut(new Error("expected " + test + "to result in an error because" + t.why));
      cb();
    });
  })
}

var deployTemplates = function(cb) {
  var deployed = 0;
  var validGroups = _.valuesIn(armTests).filter(a=>a.isValid).map(a=>a.resourceGroup);
  var allDeployed = () => {
    if (++deployed == validGroups.length)
    {
      log("all " + validGroups.length + " valid arm test scenarios deployed");
      cb();
    }
  };
  log("start deploying " + validGroups.length + " valid arm test scenarios");
  _.keys(armTests).forEach((t) => {
    deployTemplate(t, allDeployed)
  });
}

var showOperationList = (test, cb) => {
  var t = armTests[test];
  var rg = t.resourceGroup;
  var operationList = [ 'group', 'deployment', 'operation', 'list',
    rg,
    'mainTemplate',
    '--json'
  ];
  log("getting operation list result for deployment in resource group: " + rg);
  execFile(azureCli, operationList, (error, stdout, stderr) => {
    log(test, "operationListResult:" + (stdout || stderr));
    if (error || stderr) return bailOut(error || new Error(stderr));
    var errors = _(JSON.parse(stdout))
      .filter(f=>f.properties.provisioningState !== "Succeeded")
      .map(f=>f.properties.statusMessage)
      .value();
    errors.forEach(e => {
      log(test + "resulted in error: " + JSON.stringify(e, null, 2));
    })
    cb();
  });
}

var deployTemplate = (test, cb) => {
  var t = armTests[test];
  if (!t.isValid) return;
  var p = JSON.stringify(t.params)
  var rg = t.resourceGroup;
  var deployGroup = [ 'group', 'deployment', 'create',
    '--resource-group', rg,
    '--template-uri', templateUri,
    '--parameters', p,
    '--quiet',
    '--json'
  ];
  log("deploying "+ test +" in resource group: " + rg);
  execFile(azureCli, deployGroup, (error, stdout, stderr) => {
    log(test, "deployResult:" + (stdout || stderr));
    if (error || stderr)
    {
      showOperationList(test, ()=>{});
      return bailOut(error || new Error(stderr));
    }
    showOperationList(test, cb);
  });
}

gulp.task("create-log-folder", (cb) => mkdirp(logDistTmp, cb));
gulp.task("clean", ["create-log-folder"], () => del([ logDistTmp + "/**/*" ], { force: true }));

gulp.task("test", ["clean"], function(cb) {
  login(() => validateTemplates(() => deleteCurrentTestGroups(() => logout(cb))));
});

gulp.task("deploy-all", ["clean"], function(cb) {
  login(() => validateTemplates(() => deployTemplates(() => deleteCurrentTestGroups(() => logout(cb)))));
});

gulp.task("azure-cleanup", ["clean"], function(cb) {
  login(() => deleteAllTestGroups(() => logout(cb)));
});
