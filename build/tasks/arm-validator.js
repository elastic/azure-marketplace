var config = require('../.test.json');
var gulp = require("gulp");
const execFile = require('child_process').execFile;
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
var compareVersions = require('compare-versions');

var azureCli = "../node_modules/.bin/azure";
if (operatingSystem === "win32")
  azureCli = "..\\node_modules\\.bin\\azure.cmd";
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
  log(t, "parameters: " + JSON.stringify(test.parameters, null, 2));
  var testParameters = merge.recursive(true, exampleParameters, test.parameters);
  testParameters.artifactsBaseUrl.value = artifactsBaseUrl;
  testParameters.adminUsername.value = config.deployments.username;
  testParameters.adminPassword.value = config.deployments.password;
  testParameters.sshPublicKey.value = config.deployments.ssh;
  testParameters.securityBootstrapPassword.value = config.deployments.securityPassword;
  testParameters.securityAdminPassword.value = config.deployments.securityPassword;
  testParameters.securityReadPassword.value = config.deployments.securityPassword;
  testParameters.securityKibanaPassword.value = config.deployments.securityPassword;
  testParameters.securityLogstashPassword.value = config.deployments.securityPassword;
  testParameters.esVersion.value = defaultVersion;

  return {
    resourceGroup: "test-" + hostname.toLowerCase() + "-" + t.replace(".json", "") + dateFormat(new Date(), "-yyyymmdd-HHMMssl").replace("+","-"),
    location: test.location,
    isValid: test.isValid,
    why: test.why,
    deploy: test.deploy,
    params: testParameters
  }
}

var bootstrap = (cb) => {
  var allowedValues = require('../allowedValues.json');
  var versions = _.keys(allowedValues.versions);
  var defaultVersion = _.last(versions);
  git.branch(function (branch) {
    artifactsBaseUrl = "https://raw.githubusercontent.com/elastic/azure-marketplace/"+ branch + "/src";
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
    if (error || stderr) return bailOutNoCleanUp(error || new Error(stderr));
    cb();
  });
});

var logout = (cb) => {
  var logout = [ 'logout', config.arm.clientId];
  log("logging out of the  azure cli tooling")
  execFile(azureCli, logout, cb);
}

var bailOutNoCleanUp = (error)  => {
  if (!error) return;
  log(error)
  throw error;
}

var bailOut = (error, rg)  => {
  if (!error) return;
  if (!rg) log(error)
  else log("resourcegroup: " + rg + " - " + error)
  
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
      if (error || stderr) return bailOut(error || new Error(stderr), n);
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
    if (error || stderr) return bailOut(error || new Error(stderr), rg);
    log(test, "createGroupResult: " + stdout);
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
  var p = JSON.stringify(t.params);
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
      log(test, "Expected result: " + t.isValid + " because " + t.why);
      log(test, "validateResult:" + (stdout || stderr));
      if (t.isValid && (error || stderr)) return bailOut(error || new Error(stderr), rg);
      else if (!t.isValid && !(error || stderr)) return bailOut(new Error("expected " + test + "to result in an error because " + t.why), rg);
      cb();
    });
  })
}

var deployTemplates = function(cb) {
  var deployed = 0;
  var validGroups = _.valuesIn(armTests).filter(a=>a.isValid && a.deploy).map(a=>a.resourceGroup);
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
    if (error || stderr) return bailOut(error || new Error(stderr), rg);
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

var sanityCheckOutput = (test, stdout, cb) => {
  if (!stdout) return cb();
  var outputs = JSON.parse(stdout).properties.outputs;
  var checks = [];
  var checked = 0;
  var allChecked = () => { if (++checked == checks.length) cb(); };
  if (outputs.loadbalancer.value !== "N/A")
    checks.push(()=> sanityCheckExternalLoadBalancer(test, outputs.loadbalancer.value, allChecked));
  if (outputs.kibana.value !== "N/A")
    checks.push(()=> sanityCheckKibana(test, outputs.kibana.value, allChecked));
  //TODO check with ssh2 in case we are using internal loadbalancer
  if (checks.length > 0) checks.forEach(check => check());
  else cb();
}

var sanityCheckExternalLoadBalancer = (test, url, cb) => {
  var t = armTests[test];
  var rg = t.resourceGroup;
  log("checking external loadbalancer "+ url +" in resource group: " + rg);
  var superuser = compareVersions(t.params.esVersion.value,'5.0.0') >= 0 ? "elastic" : "es_admin";
  var opts = { json: true, auth: { username: superuser, password: config.deployments.securityPassword } };
  request(url, opts, (error, response, body) => {
    if (!error && response.statusCode == 200) {
      log(test, "loadBalancerResponse: " + JSON.stringify(body, null, 2));
      request(url + "/_cluster/health", opts, (error, response, body) => {
        var status = (body) ? body.status : "unknown";
        if (!error && response.statusCode == 200 && status === "green") {
          log("cluster is up and running in resource group: " + rg);
          log(test, "clusterHealthResponse: " + JSON.stringify(body, null, 2));
          var expectedTotalNodes = 3 + t.params.vmDataNodeCount.value + t.params.vmClientNodeCount.value;
          if (t.params.dataNodesAreMasterEligible.value == "Yes") expectedTotalNodes -= 3;

          var m = "expecting " + expectedTotalNodes + " total nodes in resource group: " + rg + " and found:" + body.number_of_nodes;
          log(m);
          //if (body.number_of_nodes != expectedTotalNodes) return bailOut(new Error(m));

          var m = "expecting " + t.params.vmDataNodeCount.value + " data nodes in resource group: " + rg + " and found:" + body.number_of_data_nodes;
          log(m);
          //if (body.number_of_data_nodes != t.params.vmDataNodeCount.value) return bailOut(new Error(m));
          cb();
        }
        else {
          log("cluster is NOT up and running in resource group: " + rg);
          var m = "clusterHealthResponse: status: " + status + " error: " + error;
          log(test, m);
          //bailout(error || new error(m));
          cb();
        }
      });
    }
    else
    {
      var m = "loadbalancerResponse:  error: " + error;
      log(test, m);
      //bailout(error || new error(m));
      cb();
    }
  })
}

var sanityCheckKibana = (test, url, cb) => {
  var t = armTests[test];
  var rg = t.resourceGroup;
  log("checking kibana at "+ url +" in resource group: " + rg);
  request(url + "/api/status", { json: true, }, function (error, response, body) {
    var state = (body)
      ? body.status && body.status.overall
        ? body.status.overall.state
        : body.error
            ? body.error
            : "unknown"
      : "unknown";

    log("kibana is running in resource group: " + rg + " with state:" + state);
    log(test, "kibanaResponse: " + JSON.stringify((body && body.status) ? body.status : {}, null, 2));
    //no validation just yet, kibana is most likely red straight after deployment while it retries the cluster
    //There is no guarantee kibana is not provisioned before the cluster is up
    cb();
  })
}

var deployTemplate = (test, cb) => {
  var t = armTests[test];
  if (!t.isValid || !t.deploy) return;
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
    log(test, "deployResult: " + (stdout || stderr));
    if (error || stderr)
    {
      showOperationList(test, ()=> bailOut(error || new Error(stderr), rg));
      return;
    }
    sanityCheckOutput(test, stdout, cb);
  });
}

gulp.task("create-log-folder", (cb) => mkdirp(logDistTmp, cb));
gulp.task("clean", ["create-log-folder"], () => del([ logDistTmp + "/**/*" ], { force: true }));

gulp.task("test", ["clean"], function(cb) {
  login(() => validateTemplates(() => deleteCurrentTestGroups(() => logout(cb))));
});

gulp.task("deploy-all", ["clean"], function(cb) {
  login(() => validateTemplates(() => deployTemplates(() => deleteCurrentTestGroups(() => logout(cb)))));
  //login(() => validateTemplates(() => deployTemplates(() => () => logout(cb))));
});

gulp.task("azure-cleanup", ["clean"], function(cb) {
  login(() => deleteAllTestGroups(() => logout(cb)));
});
