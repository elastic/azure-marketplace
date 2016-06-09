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
  d.vhd.Uri = d.vhd.Uri.replace(/_INDEX_/, i + 1);
  return d;
}

gulp.task("generate-data-nodes-resource", function(cb) {
  var cbCalled = 0;
  var done =function() {
    cbCalled++;
    if (cbCalled == allowedValues.dataDisks.length) cb();
  };

  allowedValues.dataDisks.forEach(function (size) {
    var t = _.cloneDeep(resourceTemplate);
    var rr = _(t.resources).find(function(r) { return r.type == "Microsoft.Resources/deployments"});
    var disks = _.range(size).map(nthDisk);
    rr.properties.parameters.dataDisks["value"].disks = disks;

    var resource = "../src/datanodes/data-node-" + size + "disk-resources.json";
    jsonfile.writeFile(resource, t, { flag: 'w' },function (err) {
      done();
    });
  });
});
