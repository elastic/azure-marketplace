var config = require('../.test.json');
var gulp = require("gulp");
var fs = require('fs');
var _ = require('lodash');
var dateFormat = require("dateformat");
var git = require('git-rev')
var hostname = require("os").hostname();
var az = require("./lib/az");
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

  // Some parameters are longer than the max allowed characters for cmd on Windows.
  // Persist to file and pass the file path for parameters
  var resourceGroup = "test-" + hostname.toLowerCase() + "-" + t.replace(".json", "") + dateFormat(new Date(), "-yyyymmdd-HHMMssl").replace("+","-")
  var parametersFile = path.resolve(logDistTmp + "/" + resourceGroup + ".json");
  fs.writeFileSync(parametersFile, JSON.stringify(params, null, 2));

  return {
    location: "westeurope",
    resourceGroup: resourceGroup,
    templateUri:  artifactsBaseUrl + "/mainTemplate.json",
    params: params,
    paramsFile: parametersFile
  }
}

var bootstrap = (cb) => {
  var version = [ "--version" ];
  az(version, (error, stdout, stderr) => {
    if (error || stderr) return bailOut(error || new Error(stderr));
    log(`Using ${stdout.split('\n')[0]}` );

    git.branch(function (branch) {
      var artifactsBaseUrl = `https://raw.githubusercontent.com/elastic/azure-marketplace/${branch}/src`;
      var test = bootstrapTest(artifactsBaseUrl);
      cb(test);
    })
  });
};

var login = (cb) => bootstrap((test) => {
  var login = [ 'login', '--service-principal',
    '--username', config.arm.clientId,
    '--password', config.arm.clientSecret,
    '--tenant', config.arm.tenantId
  ];

  log("logging into azure cli tooling")
  az(login, (error, stdout, stderr) => {
    if (error || stderr) return bailOut(error || new Error(stderr), true);
    cb(test);
  });
});

var logout = (cb) => {
  var logout = [ 'logout',
    '--username', config.arm.clientId
  ];
  log("logging out of azure cli tooling")
  az(logout, cb);
}

var bailOut = (error)  => {
  if (!error) return;
  log(error);
  logout(() => { throw error; });
}

var createResourceGroup = (test, cb) => {
  var rg = test.resourceGroup;
  var location = test.location;
  var createGroup = [ 'group', 'create',
    '--resource-group', rg,
    '--location', location,
    '--out', 'json'
  ];
  log("creating resource group: " + rg);
  az(createGroup, (error, stdout, stderr) => {
    if (error || stderr) return bailOut(error || new Error(stderr));

    if (!stdout) return bailOut(new Error("No output returned when creating resourceGroup: " + rg));

    log("createGroupResult: " + stdout);
    var result = JSON.parse(stdout);
    if (result.properties.provisioningState != "Succeeded") return bailOut(new Error("failed to create resourceGroup: " + rg));
    cb();
  });
}

var validateTemplate = (test, cb) => {
  var rg = test.resourceGroup;
  createResourceGroup(test, () => {
    var validateGroup = [ 'group', 'deployment', 'validate',
      '--resource-group', rg,
      '--template-uri', test.templateUri,
      '--parameters', '@' + test.paramsFile,
      '--out', 'json'
    ];
    log("validating resource group: " + rg);
    az(validateGroup, (error, stdout, stderr) => {
      log("validation errors:" + (error || stderr));
      if ((error || stderr)) return bailOut(error || new Error(stderr));
      cb(test);
    });
  })
}
var showOperationList = (test, cb) => {
  var rg = test.resourceGroup;
  var operationList = [ 'group', 'deployment', 'list',
    '--resource-group', rg,
    //'mainTemplate',
    '--out', 'json'
  ];
  log("getting operation list result for deployment in resource group: " + rg);
  az(operationList, (error, stdout, stderr) => {
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
  var rg = test.resourceGroup;
  var deployGroup = [ 'group', 'deployment', 'create',
    '--resource-group', rg,
    '--template-uri', test.templateUri,
    '--parameters', '@' + test.paramsFile,
    //'--no-wait',
    '--out', 'json'
  ];
  log("deploying in resource group: " + rg);
  az(deployGroup, (error, stdout, stderr) => {
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
