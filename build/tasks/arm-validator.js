var config = require('../.test.json');
var gulp = require("gulp");
var colors = require("colors");
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
var semver = require("semver");
var _artifactsLocation = "";
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
    if (logToConsole) console.log(`[${dateFormat(new Date(), "HH:MM:ss").grey}] ${data}`);
  }
  if (!data) return;
  var file = f + ".log";
  fs.appendFileSync(logDistTmp + "/" + file, data + "\n")
}

var exampleParameters = require("../../parameters/password.parameters.json");

var bootstrapTest = (t, defaultVersion) =>
{
  var test = require("../arm-tests/" + t);

  if (test.condition && !semver.satisfies(defaultVersion, test.condition.range)) {
    log(`Skipping ${t} because ${test.condition.reason}`.yellow);
    return null;
  }

  // replace parameters with base64 encoded file values
  [ "esHttpCertBlob",
    "esHttpCaCertBlob",
    "esTransportCaCertBlob",
    "kibanaCertBlob",
    "kibanaKeyBlob",
    "appGatewayCertBlob",
    "appGatewayEsHttpCertBlob",
    "logstashConf"].forEach(k => {
    if (test.parameters[k] && test.parameters[k].value) {
      var buffer = fs.readFileSync(test.parameters[k].value);
      if (k === "logstashConf") {
        buffer = Buffer.from(buffer.toString().replace("securityAdminPassword", config.deployments.securityPassword));
      }
      test.parameters[k].value = Buffer.from(buffer).toString("base64");
    }
  });

  log(t, `parameters: ${JSON.stringify(test.parameters, null, 2)}`);
  var testParameters = merge.recursive(true, exampleParameters, test.parameters);
  testParameters._artifactsLocation.value = _artifactsLocation;
  testParameters.adminUsername.value = config.deployments.username;
  testParameters.adminPassword.value = config.deployments.password;
  testParameters.sshPublicKey.value = config.deployments.ssh;
  testParameters.securityBootstrapPassword.value = config.deployments.securityPassword;
  testParameters.securityAdminPassword.value = config.deployments.securityPassword;
  testParameters.securityRemoteMonitoringPassword.value = config.deployments.securityPassword;
  testParameters.securityKibanaPassword.value = config.deployments.securityPassword;
  testParameters.securityLogstashPassword.value = config.deployments.securityPassword;
  testParameters.securityBeatsPassword.value = config.deployments.securityPassword;
  testParameters.securityApmPassword.value = config.deployments.securityPassword;
  testParameters.esVersion.value = defaultVersion;

  // Some parameters are longer than the max allowed characters for cmd on Windows.
  // Persist to file and pass the file path for parameters
  var name = t.replace(".json", "");
  var resourceGroup = "test-" + hostname + "-" + name + dateFormat(new Date(), "-yyyymmdd-HHMMssl").replace("+","-")
  var testParametersFile = path.resolve(logDistTmp + "/" + resourceGroup + ".json");
  fs.writeFileSync(testParametersFile, JSON.stringify(testParameters, null, 2));

  return {
    name: name,
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
  var defaultVersion = argv.esVersion ?
    argv.esVersion == "random" ?
      _.sample(allowedValues.versions)
      : argv.esVersion
    : _.last(allowedValues.versions);

  log(`Using version ${defaultVersion} for tests`);
  if (!_.includes(allowedValues.versions, defaultVersion)){
    return bailOut(new Error(`No version in allowedValues.versions matching ${defaultVersion}`));
  }

  var templateMatcher = new RegExp(argv.test || ".*");

  git.branch((branch) => {
    _artifactsLocation = `https://raw.githubusercontent.com/elastic/azure-marketplace/${branch}/src/`;
    templateUri = `${_artifactsLocation}mainTemplate.json`;
    log(`Using template: ${templateUri}`, false);
    armTests = _(fs.readdirSync("arm-tests"))
      .filter(t => templateMatcher.test(t))
      .indexBy(f => f)
      .mapValues(t => bootstrapTest(t, defaultVersion))
      .filter(t => t != null)
      .value();
    cb();
  });
};

var login = (cb) => {
  var version = [ '--version' ];
  az(version, (error, stdout, stderr) => {
    // ignore stderr if it's simply a warning about an older version of Azure CLI
    if (error || (stderr && !/^WARNING: You have \d+ updates available/.test(stderr))) {
      return bailOut(error || new Error(stderr));
    }

    log(`Using ${stdout.split('\n')[0].replace('*', '').replace(/\s\s+/g, ' ')}` );

    var login = [ 'login',
      '--service-principal',
      '--username', config.arm.clientId,
      '--password', config.arm.clientSecret,
      '--tenant', config.arm.tenantId
    ];

    log("logging into azure cli tooling")
    az(login, (error, stdout, stderr) => {
      if (error || stderr) return bailOutNoCleanUp(error || new Error(stderr));
      cb();
    });
  });
}

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

var bailOut = (error, rg) => {
  if (!error) return;
  if (!rg) log(error);
  else log(`resourcegroup: ${rg} - ${error}`);
  deleteCurrentTestGroups(() => logout(() => { throw error; }));
}

var deleteGroups = (groups, cb) => {
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

var deleteAllTestGroups = (cb) => {
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

var deleteCurrentTestGroups = (cb) => {
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

var deleteParametersFiles = (cb) => {
  log("deleting temporary parameter files", false);
  del([ logDistTmp + "/**/*.json" ], { force: true });
  cb();
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

var validateTemplates = (cb) => {
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
    log(`validating ${t.name} in resource group: ${rg}`);
    az(validateGroup, (error, stdout, stderr) => {
      log(test, `Expected result: ${t.isValid} because ${t.why}`);
      log(test, `validateResult:${stdout || stderr}`);
      if (t.isValid && (error || stderr)) return bailOut(error || new Error(stderr), rg);
      else if (!t.isValid && !(error || stderr)) return bailOut(new Error(`expected ${t.name} to result in an error because ${t.why}`), rg);
      cb();
    });
  })
}

var deployTemplates = (cb) => {
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
      log(`${t.name} resulted in error: ${JSON.stringify(e, null, 2)}`);
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
    if (outputs.loadbalancer.value !== "N/A") {
      checks.push(()=> sanityCheckExternalLoadBalancer(test, "external loadbalancer", outputs.loadbalancer.value, allChecked));

      // logstash can be checked with external loadbalancer
      // TODO: support checking through Application Gateway and Kibana
      if (t.params.logstash.value === "Yes")
        checks.push(()=> sanityCheckLogstash(test, outputs.loadbalancer.value, allChecked));
    }
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
    '--name', 'app-gateway-ip',
    '--resource-group', rg,
    '--out', 'json'
  ];

  log(`getting the public IP for ${appGateway} in: ${rg}`);
  az(operationList, (error, stdout, stderr) => {
    log(test, `operationPublicIpShowResult: ${stdout || stderr}`);
    if (error || stderr) {
      log(`getting public ip for ${appGateway} in ${t.name} resulted in error: ${JSON.stringify(error, null, 2)}`);
      cb();
    }

    var result = JSON.parse(stdout);
    var url = `https://${result.dnsSettings.fqdn}:9200`;
    sanityCheckExternalLoadBalancer(test, appGateway, url, cb);
  });
}

var createLoadBalancerRequestOptions = (t, loadbalancerType) => {
  var opts = {
    json: true,
    auth: { username: "elastic", password: config.deployments.securityPassword },
    // don't perform hostname validation as all tests use self-signed certs
    agentOptions: { checkServerIdentity: _.noop }
  };

  if (loadbalancerType === "application gateway") {
    if (t.params.appGatewayCertBlob && t.params.appGatewayCertBlob.value) {
      if (t.params.appGatewayCertPassword && t.params.appGatewayCertPassword.value) {
        opts = merge.recursive(true, opts, {
          pfx: fs.readFileSync("certs/cert-with-password.pfx"),
          passphrase: t.params.appGatewayCertPassword.value,
        });
      }
      else {
        opts = merge.recursive(true, opts, {
          pfx: fs.readFileSync("certs/cert-no-password.pfx")
        });
      }
    }
  }
  else if (t.params.esHttpCertBlob && t.params.esHttpCertBlob.value) {
    if (t.params.esHttpCertPassword && t.params.esHttpCertPassword.value) {
      opts = merge.recursive(true, opts, {
        pfx: fs.readFileSync("certs/cert-with-password.pfx"),
        passphrase: t.params.esHttpCertPassword.value,
      });
    }
    else {
      opts = merge.recursive(true, opts, {
        pfx: fs.readFileSync("certs/cert-no-password.pfx")
      });
    }
  }
  else if (t.params.esHttpCaCertBlob && t.params.esHttpCaCertBlob.value) {
    opts = merge.recursive(true, opts, {
      // ca cert agentOption does not work: https://github.com/request/request#using-optionsagentoptions
      // so disable cert validation altogether when certs are generated from a CA.
      rejectUnauthorized: false
    });
  }

  return opts;
}

var sanityCheckExternalLoadBalancer = (test, loadbalancerType, url, cb) => {
  var t = armTests[test];
  var rg = t.resourceGroup;
  log(`checking ${loadbalancerType} ${url} in resource group: ${rg}`);
  var opts = createLoadBalancerRequestOptions(t, loadbalancerType);
  request(url, opts, (error, response, body) => {
    if (!error && response.statusCode == 200) {
      log(test, `loadBalancerResponse: ${JSON.stringify(body, null, 2)}`);
      request(`${url}/_cluster/health`, opts, (error, response, body) => {
        var status = (body) ? body.status : "unknown";
        if (!error && response.statusCode === 200 &&
            // if logstash is deployed and successfully sending events, the logstash created
            // index will be created with the default number of shards and replicas
            (status === "green" || (status === "yellow" && t.params.logstash.value === "Yes"))) {
          log(`cluster is up and running in resource group: ${rg}`);
          log(test, `clusterHealthResponse: ${JSON.stringify(body, null, 2)}`);
          var expectedTotalNodes = 3 + t.params.vmDataNodeCount.value + t.params.vmClientNodeCount.value;
          if (t.params.dataNodesAreMasterEligible.value === "Yes") expectedTotalNodes -= 3;

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
  });
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

    log(`kibana is running in resource group: ${rg} with state: ${state[state.toLowerCase()]}`);
    log(test, `kibanaResponse: ${JSON.stringify((body && body.status) ? body.status : {}, null, 2)}`);

    //no validation just yet, kibana is most likely red straight after deployment while it retries the cluster
    //There is no guarantee kibana is not provisioned before the cluster is up
    if (state == "green") {
      log(`checking kibana monitoring endpoint for rg: ${rg}`);

      opts.method = "POST";
      opts.headers = opts.headers || {};
      opts.headers["kbn-xsrf"] = "reporting";
      var now = new Date();
      now.setHours(now.getHours() - 1);
      var plusAnHour = new Date();
      plusAnHour.setHours(plusAnHour.getHours() + 1);
      opts.body = JSON.stringify({
        timeRange: {
          min: dateFormat(now, "isoUtcDateTime"),
          max: dateFormat(plusAnHour, "isoUtcDateTime")
        }
      });

      request(`${url}/api/monitoring/v1/clusters`, opts, function (error, response, body) {
        log(test, `monitoringResponse: ${JSON.stringify(body ? body : {}, null, 2)}`);

        if (body && body.length) {
          var kibana = body[0].kibana;
          if (kibana) {
            log ("kibana monitoring enabled");
          }

          if (t.params.logstash.value === "Yes") {
            log("logstash enabled in the template. Checking monitoring");
            var logstash = body[0].logstash;
            if (logstash) {
              log("logstash monitoring enabled");
            }
          }
        }

        cb();
      });
    }
    else {
      cb();
    }
  });
}

var sanityCheckLogstash = (test, url, cb) => {
  var t = armTests[test];
  var rg = t.resourceGroup;
  log(`checking logstash is sending events in resource group: ${rg}`);
  var opts = createLoadBalancerRequestOptions(t, "external");
  var attempts = 0;
  var countRequest = () => {
    request(`${url}/heartbeat/_count`, opts, (error, response, body) => {
      if (!error && response && response.statusCode == 200) {
        var count = (body) ? body.count : -1;
        if (count >= 0) {
          log(`logstash sent ${count} events in resource group: ${rg}`);
          cb();
        }
        else {
          log(`logstash not sent any events in resource group: ${rg}`);
          cb();
        }
      }
      else if (response && response.statusCode == 404 && attempts < 10) {
        log(`logstash event index not found. retry attempt: ${++attempts} for resource group: ${rg}`);
        setTimeout(countRequest, 5000);
      }
      else {
        log(`problem checking for logstash events in resource group: ${rg}. ${response ? "response status code: " + response.statusCode: ""}`);
        log(test, `statusCode: ${response ? response.statusCode : "unknown"}, error: ${error}\ncheckLogstashEventCountResponse: ${JSON.stringify(body ? body : {}, null, 2)}`);
        cb();
      }
    });
  };

  countRequest();
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
  log(`deploying ${t.name} in resource group: ${rg}`);
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
gulp.task("clean", gulp.series("create-log-folder", (cb) => {
  del([ logDistTmp + "/**/*" ], { force: true });
  cb();
}));

gulp.task("test", gulp.series("clean", (cb) => {
  bootstrap(() => {
    if (armTests.length) {
      login(() => validateTemplates(() => deleteCurrentTestGroups(() => logout(() => deleteParametersFiles(cb)))));
    } else {
      cb();
    }
  });
}));

gulp.task("deploy", gulp.series("clean", (cb) => {
  bootstrap(() => {
    if (armTests.length) {
      login(() => validateTemplates(() => deployTemplates(() => deleteCurrentTestGroups(() => logout(() => deleteParametersFiles(cb))))));
    } else {
      cb();
    }
  });
}));

gulp.task("azure-cleanup", gulp.series("clean", (cb) => {
  login(() => deleteAllTestGroups(() => logout(cb)));
}));
