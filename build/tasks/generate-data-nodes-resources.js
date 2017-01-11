var gulp = require("gulp");
var jsonfile = require('jsonfile');
var _ = require('lodash');
var replace = require('gulp-replace');

jsonfile.spaces = 2;

var resourceTemplate = require("../../src/datanodes/data-node-template.json");
var allowedValues = require('../allowedValues.json');
var resource = _(resourceTemplate.resources).find(function(r) { return r.type == "Microsoft.Resources/deployments"});
var dataDiskTemplate = resource.properties.parameters.dataDisks.value.disks[0];
var nthDisk = function(i) {
  var d = _.cloneDeep(dataDiskTemplate);
  d.lun = i;
  d.name = d.name.replace(/_INDEX_/, i + 1);
  d.vhd.uri = d.vhd.uri.replace(/_INDEX_/, i + 1);
  return d;
}

var dataNodeWithDataDisk = function (size, done) {
  var t = _.cloneDeep(resourceTemplate);
  var rr = _(t.resources).find(function(r) { return r.type == "Microsoft.Resources/deployments"});
  var disks = _.range(size).map(nthDisk);
  rr.properties.parameters.dataDisks["value"].disks = disks;

  var nodesPerStorageAccount = Math.max(1, (10 - ((Math.log(size) / Math.log(2)) * 2)));
  t.variables.nodesPerStorageAccount = nodesPerStorageAccount;

  var resource = "../src/datanodes/data-node-" + size + "disk-resources.json";
  jsonfile.writeFile(resource, t, { flag: 'w' },function (err) {
    done();
  });
};
var dataNodeWithoutDataDisk = function (size, done) {
  var t = _.cloneDeep(resourceTemplate);
  t.resources = _(t.resources).filter(r=>r.type != "Microsoft.Storage/storageAccounts").value();
  var rr = _(t.resources).find(function(r) { return r.type == "Microsoft.Resources/deployments"});
  rr.properties.parameters.dataDisks = null;
  delete rr.properties.parameters.dataDisks;
  rr.dependsOn = [rr.dependsOn[0]];

  delete t.variables.nodesPerStorageAccount;
  delete t.variables.storageAccountPrefix;
  delete t.variables.storageAccountPrefixCount;
  delete t.variables.newStorageAccountNamePrefix;

  var resource = "../src/datanodes/data-node-" + size + "disk-resources.json";
  jsonfile.writeFile(resource, t, { flag: 'w' },function (err) {
    done();
  });
};

gulp.task("generate-data-nodes-resource", function(cb) {
  var cbCalled = 0;
  var done =function() {
    cbCalled++;
    if (cbCalled == allowedValues.dataDisks.length + 1) cb();
  };

  allowedValues.dataDisks.forEach(function (size) {
    dataNodeWithDataDisk(size, done);
  });
  dataNodeWithoutDataDisk(0, done);
});
