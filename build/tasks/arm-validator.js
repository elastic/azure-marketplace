var config = require('../.test.json');
var gulp = require("gulp");
var fs = require('fs');
var path = require('path');
var _ = require('lodash');
var dateFormat = require("dateformat");
var git = require('git-rev')
var merge = require('merge');
var mkdirp = require('mkdirp');
var del = require('del');
var request = require('request');
var hostname = require("os").hostname().toLowerCase();
var argv = require('yargs').argv;
var az = require("./lib/az");
var artifactsBaseUrl = "";
var templateUri = "";
var armTests = {};
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

  // replace cert parameters with values with base64 encoded certs
  [
    "esHttpCertBlob",
    "esHttpCaCertBlob",
    "esTransportCaCertBlob",
    "kibanaCertBlob",
    "kibanaKeyBlob",
    "appGatewayCertBlob",
    "appGatewayEsHttpCertBlob"].forEach(k => {
    if (test.parameters[k] && test.parameters[k].value) {
      var cert = fs.readFileSync("certs/" + test.parameters[k].value);
      test.parameters[k].value = new Buffer(cert).toString("base64");
    }
  });

  log(t, `parameters: ${JSON.stringify(test.parameters, null, 2)}`);
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

  // Some parameters are longer than the max allowed characters for cmd on Windows.
  // Persist to file and pass the file path for parameters
  var resourceGroup = "test-" + hostname + "-" + t.replace(".json", "") + dateFormat(new Date(), "-yyyymmdd-HHMMssl").replace("+","-")
  var testParametersFile = path.resolve(logDistTmp + "/" + resourceGroup + ".json");
  fs.writeFileSync(testParametersFile, JSON.stringify(testParameters, null, 2));

  return {
    resourceGroup: resourceGroup,
    location: test.location,
    isValid: test.isValid,
    why: test.why,
    deploy: test.deploy,
    params: testParameters,
    paramsFile: testParametersFile
  }
}

var bootstrap = (cb) => {
  var allowedValues = require('../allowedValues.json');
  var defaultVersion = argv.version ?
    argv.version == "random" ?
      _.sample(allowedValues.versions)
      : argv.version
    : _.last(allowedValues.versions);

  if (!_.includes(allowedValues.versions, defaultVersion)){
    return bailOut(new Error(`No version in allowedValues.versions matching ${defaultVersion}`));
  }

  var version = [ '--version' ];
  az(version, (error, stdout, stderr) => {
    if (error || stderr) return bailOut(error || new Error(stderr));
    log(`Using ${stdout.split('\n')[0]}` );

    var templateMatcher = new RegExp(argv.test || ".*");

    git.branch(function (branch) {
      artifactsBaseUrl = `https://raw.githubusercontent.com/elastic/azure-marketplace/${branch}/src`;
      templateUri = `${artifactsBaseUrl}/mainTemplate.json`;
      log(`Using template: ${templateUri}`, false);
      armTests = _(fs.readdirSync("arm-tests"))
        .filter(t => templateMatcher.test(t))
        .indexBy((f) => f)
        .mapValues(t => bootstrapTest(t, defaultVersion))
        .value();
      cb();
    })
  });
};

var login = (cb) => bootstrap(() => {
  var login = [ 'login', '--service-principal',
    '--username', config.arm.clientId,
    '--password', config.arm.clientSecret,
    '--tenant', config.arm.tenantId,
    //'-e', config.arm.environment
  ];

  log("logging into azure cli tooling")
  az(login, (error, stdout, stderr) => {
    if (error || stderr) return bailOutNoCleanUp(error || new Error(stderr));
    cb();
  });
});

var logout = (cb) => {
  var logout = [ 'logout',
    '--username', config.arm.clientId
  ];
  log("logging out of azure cli tooling")
  az(logout, cb);
}

var bailOutNoCleanUp = (error)  => {
  if (!error) return;
  log(error)
  throw error;
}

var bailOut = (error, rg)  => {
  if (!error) return;
  if (!rg) log(error)
  else log(`resourcegroup: ${rg} - ${error}`)

  var cb = () => logout(() => { throw error; })

  var groups = _.valuesIn(armTests).map(a=>a.resourceGroup);
  if (groups.length > 0) deleteGroups(groups, cb);
  else cb();
}

var deleteGroups = function (groups, cb) {
  var deleted = 0;
  var allDeleted = () => { if (++deleted == groups.length) cb(); };
  log(`deleting ${groups.length} resource groups`);
  if (groups.length == 0) cb();
  else groups.forEach(n=> {
    var groupDelete = [ 'group', 'delete',
      '--name', 'mainTemplate',
      '--resource-group', n,
      '--yes',
      '--no-wait',
      '--out', 'json'];
    log(`deleting resource group: ${n}`);
    az(groupDelete, (error, stdout, stderr) => {
      if (error || stderr) return bailOut(error || new Error(stderr), n);
      log(`deleted resource group: ${n}`, false);
      allDeleted();
    });
  });
}

var deleteAllTestGroups = function (cb) {
  var startsWithPattern = `test-${hostname}-`;
  var groupList = [ 'group', 'list',
    // double quotes needed around JMESPATH expression
    '--query', `"[?name | starts_with(@,'${startsWithPattern}')]"`,
    '--out', 'json'
  ];
  log(`getting a list of all resources that start with ${startsWithPattern}`);
  az(groupList, (error, stdout, stderr) => {
    if (error || stderr) return bailOut(error || new Error(stderr));
    var result = JSON.parse(stdout);
    var testGroups = _(result).map(g=>g.name).value();
    if (testGroups.length === 0) log("found no lingering resource groups", false);
    else log(`found lingering resource groups: ${testGroups}`, false);
    deleteGroups(testGroups, cb);
  });
}

var deleteCurrentTestGroups = function(cb)
{
  var groups = _.valuesIn(armTests).map(a=>a.resourceGroup);
  if (argv.nodestroy) {
    log(`not destroying ${groups.length} resource groups as --nodestroy parameter passed.`, false);
    log("----------------------------------------------");
    log("| DELETE THESE RESOURCE GROUPS WHEN FINISHED |");
    log("|                                            |")
    log("| $ npm run azure-cleanup                    |")
    log("----------------------------------------------");
    cb();
  }
  else {
    log(`deleting current run groups: ${groups}`, true);
    deleteGroups(groups, cb);
  }
}

var createResourceGroup = (test, cb) => {
  var rg = armTests[test].resourceGroup;
  var location = armTests[test].location;
  var createGroup = [ 'group', 'create',
    '--name', 'mainTemplate',
    '--resource-group', rg,
    '--location', location,
    '--out', 'json'];
  log(`creating resource group: ${rg}`);
  az(createGroup, (error, stdout, stderr) => {
    if (error || stderr) return bailOut(error || new Error(stderr), rg);
    log(test, `createGroupResult: ${stdout}`);
    var result = JSON.parse(stdout);
    if (result.properties.provisioningState != "Succeeded") return bailOut(new Error(`failed to create resourceGroup: ${rg}`));
    cb();
  });
}

var validateTemplates = function(cb) {
  var validated = 0;
  var groups = _.valuesIn(armTests).map(a=>a.resourceGroup);
  var allValidated = () => {
    if (++validated == groups.length)
    {
      log(`all ${groups.length} arm test scenarios validated`);
      cb();
    }
  };
  log(`start validating ${groups.length} arm test scenarios`);
  _.keys(armTests).forEach((t) => {
    validateTemplate(t, allValidated)
  });
}

var validateTemplate = (test, cb) => {
  var t = armTests[test];
  var rg = t.resourceGroup;
  createResourceGroup(test, () => {
    var validateGroup = [ 'group', 'deployment', 'validate',
      '--resource-group', rg,
      '--template-uri', templateUri,
      '--parameters', '@' + t.paramsFile,
      '--out', 'json'
    ];
    log(`validating ${test} in resource group: ${rg}`);
    az(validateGroup, (error, stdout, stderr) => {
      log(test, `Expected result: ${t.isValid} because ${t.why}`);
      log(test, `validateResult:${stdout || stderr}`);
      if (t.isValid && (error || stderr)) return bailOut(error || new Error(stderr), rg);
      else if (!t.isValid && !(error || stderr)) return bailOut(new Error(`expected ${test} to result in an error because ${t.why}`), rg);
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
      log(`all ${validGroups.length} valid arm test scenarios deployed`);
      cb();
    }
  };
  log(`start deploying ${validGroups.length} valid arm test scenarios`);
  _.keys(armTests).forEach((t) => {
    deployTemplate(t, allDeployed)
  });
}

var showOperationList = (test, cb) => {
  var t = armTests[test];
  var rg = t.resourceGroup;
  var operationList = [ 'group', 'deployment', 'operation', 'list',
    '--name', 'mainTemplate',
    '--resource-group', rg,
    '--out', 'json'
  ];
  log(`getting operation list result for deployment in resource group: ${rg}`);
  az(operationList, (error, stdout, stderr) => {
    log(test, `operationListResult: ${stdout || stderr}`);
    if (error || stderr) return bailOut(error || new Error(stderr), rg);
    var errors = _(JSON.parse(stdout))
      .filter(f=>f.properties.provisioningState !== "Succeeded")
      .map(f=>f.properties.statusMessage)
      .value();
    errors.forEach(e => {
      log(`${test} resulted in error: ${JSON.stringify(e, null, 2)}`);
    })
    cb();
  });
}

var sanityCheckDeployment = (test, stdout, cb) => {
  var checks = [];
  var checked = 0;
  var allChecked = () => { if (++checked == checks.length) cb(); };
  var t = armTests[test];

  if (stdout) {
    var outputs = JSON.parse(stdout).properties.outputs;
    if (outputs.loadbalancer.value !== "N/A")
        checks.push(()=> sanityCheckExternalLoadBalancer(test, "external loadbalancer", outputs.loadbalancer.value, allChecked));
    if (outputs.kibana.value !== "N/A")
      checks.push(()=> sanityCheckKibana(test, outputs.kibana.value, allChecked));
  }

  if (t.params.loadBalancerType.value === "gateway")
    checks.push(()=> sanityCheckApplicationGateway(test, allChecked));

  //TODO check with ssh2 in case we are using internal loadbalancer
  if (checks.length > 0) checks.forEach(check => check());
  else cb();
}

var sanityCheckApplicationGateway = (test, cb) => {
  var t = armTests[test];
  var rg = t.resourceGroup;
  var appGateway = "application gateway";

  var operationList = [ 'network', 'public-ip', 'show',
    '--name', 'es-app-gateway-ip',
    '--resource-group', rg,
    '--out', 'json'
  ];

  log(`getting the public IP for ${appGateway} in: ${rg}`);
  az(operationList, (error, stdout, stderr) => {
    log(test, `operationPublicIpShowResult: ${stdout || stderr}`);
    if (error || stderr) {
      log(`getting public ip for ${appGateway} in ${test} resulted in error: ${JSON.stringify(e, null, 2)}`);
      cb();
    }

    var result = JSON.parse(stdout);
    var url = `https://${result.dnsSettings.fqdn}:9200`;
    sanityCheckExternalLoadBalancer(test, appGateway, url, cb);
  });
}

var sanityCheckExternalLoadBalancer = (test, loadbalancerType, url, cb) => {
  var t = armTests[test];
  var rg = t.resourceGroup;
  log(`checking ${loadbalancerType} ${url} in resource group: ${rg}`);
  var opts = {
    json: true,
    auth: { username: "elastic", password: config.deployments.securityPassword },
    agentOptions: { checkServerIdentity: _.noop }
  };

  var certParams = {
    blob: (loadbalancerType === "application gateway") ? "appGatewayCertBlob": "esHttpCertBlob",
    passphrase: (loadbalancerType === "application gateway") ? "appGatewayCertPassword": "esHttpCertPassword",
  };

  if (t.params[certParams.blob] && t.params[certParams.blob].value) {
    if (t.params[certParams.passphrase] && t.params[certParams.passphrase].value) {
      opts = merge.recursive(true, opts, {
        pfx: fs.readFileSync("certs/cert-with-password.pfx"),
        passphrase: t.params[certParams.passphrase].value,
      });
    }
    else {
      opts = merge.recursive(true, opts, {
        pfx: fs.readFileSync("certs/cert-no-password.pfx")
      });
    }
  }

  request(url, opts, (error, response, body) => {
    if (!error && response.statusCode == 200) {
      log(test, `loadBalancerResponse: ${JSON.stringify(body, null, 2)}`);
      request(`${url}/_cluster/health`, opts, (error, response, body) => {
        var status = (body) ? body.status : "unknown";
        if (!error && response.statusCode == 200 && status === "green") {
          log(`cluster is up and running in resource group: ${rg}`);
          log(test, `clusterHealthResponse: ${JSON.stringify(body, null, 2)}`);
          var expectedTotalNodes = 3 + t.params.vmDataNodeCount.value + t.params.vmClientNodeCount.value;
          if (t.params.dataNodesAreMasterEligible.value == "Yes") expectedTotalNodes -= 3;

          log(`expecting ${expectedTotalNodes} total nodes in resource group: ${rg} and found: ${body.number_of_nodes}`);
          //if (body.number_of_nodes != expectedTotalNodes) return bailOut(new Error(m));

          log(`expecting ${t.params.vmDataNodeCount.value} data nodes in resource group: ${rg} and found: ${body.number_of_data_nodes}`);
          //if (body.number_of_data_nodes != t.params.vmDataNodeCount.value) return bailOut(new Error(m));
          cb();
        }
        else {
          log(`cluster is NOT up and running in resource group: ${rg}`);
          log(test, `clusterHealthResponse: status: ${status} error: ${error}`);
          //bailout(error || new error(m));
          cb();
        }
      });
    }
    else {
      log(test, `loadbalancerResponse:  error: ${error}`);
      //bailout(error || new error(m));
      cb();
    }
  })
}

var sanityCheckKibana = (test, url, cb) => {
  var t = armTests[test];
  var rg = t.resourceGroup;
  log(`checking kibana at ${url} in resource group: ${rg}`);
  var opts = {
    json: true,
    auth: { username: "elastic", password: config.deployments.securityPassword },
    agentOptions: { checkServerIdentity: _.noop }
  };

  if (t.params.kibanaCertBlob && t.params.kibanaCertBlob.value) {
    opts.ca = (t.params.kibanaKeyPassphrase && t.params.kibanaKeyPassphrase.value) ?
      fs.readFileSync("certs/cert-with-password-ca.crt") :
      fs.readFileSync("certs/cert-no-password-ca.crt");
  }

  request(`${url}/api/status`, opts, function (error, response, body) {
    var state = (body)
      ? body.status && body.status.overall
        ? body.status.overall.state
        : body.error
            ? body.error
            : "unknown"
      : "unknown";

    log(`kibana is running in resource group: ${rg} with state: ${state}`);
    log(test, `kibanaResponse: ${JSON.stringify((body && body.status) ? body.status : {}, null, 2)}`);
    //no validation just yet, kibana is most likely red straight after deployment while it retries the cluster
    //There is no guarantee kibana is not provisioned before the cluster is up
    cb();
  });
}

var deployTemplate = (test, cb) => {
  var t = armTests[test];
  if (!t.isValid || !t.deploy) return;
  var rg = t.resourceGroup;
  var deployGroup = [ 'group', 'deployment', 'create',
    '--resource-group', rg,
    '--template-uri', templateUri,
    '--parameters', '@' + t.paramsFile,
    '--out', 'json'
  ];
  log(`deploying ${test} in resource group: ${rg}`);
  az(deployGroup, (error, stdout, stderr) => {
    log(test, `deployResult: ${stdout || stderr}`);
    if (error || stderr) {
      showOperationList(test, ()=> bailOut(error || new Error(stderr), rg));
      return;
    }
    sanityCheckDeployment(test, stdout, cb);
  });
}

gulp.task("create-log-folder", (cb) => mkdirp(logDistTmp, cb));
gulp.task("clean", ["create-log-folder"], () => del([ logDistTmp + "/**/*" ], { force: true }));

gulp.task("test", ["clean"], function(cb) {
  login(() => validateTemplates(() => deleteCurrentTestGroups(() => logout(cb))));
});

gulp.task("deploy", ["clean"], function(cb) {
  login(() => validateTemplates(() => deployTemplates(() => deleteCurrentTestGroups(() => logout(cb)))));
});

gulp.task("azure-cleanup", ["clean"], function(cb) {
  login(() => deleteAllTestGroups(() => logout(cb)));
});
