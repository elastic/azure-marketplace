var config = require('../.test.json');

var msRestAzure = require('ms-rest-azure');
var AzureEnvironment = require('ms-rest-azure').AzureEnvironment;
var azure = require("azure");

var gulp = require("gulp");
var eclint = require("eclint");
var jsonlint = require("gulp-jsonlint");
var zip = require("gulp-zip");
var dateFormat = require("dateformat");
var addsrc = require('gulp-add-src');

gulp.task("test", function(cb) {
  cb();
});
