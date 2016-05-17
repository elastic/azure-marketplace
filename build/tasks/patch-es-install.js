var gulp = require("gulp");
var gutil = require('gulp-util');
var _ = require('lodash');
var replace = require('gulp-replace');
var request = require('request');

var installElasticsearchBash = "../src/scripts/elasticsearch-ubuntu-install.sh";

var allowedValues = require('../allowedValues.json');

  function expandUrl(shortUrl, cb) {
        request( { method: "HEAD", url: shortUrl, followAllRedirects: true },
            function (error, response) {
                cb(response.request.href);
            });
    }

gulp.task('link-checker', function (cb) {
  var urls = _.keys(allowedValues.versions)
    .map(function(k) { return { version: k, url: allowedValues.versions[k].downloadUrl } })
    .filter(function(v) { return !!v.url })

  var called = urls.length;
  var urlsCallback = function(error) { called--; if (called == 0 || error) cb(error); };
  var expandUrl = function (shortUrl, v) {
    request( { method: "HEAD", url: shortUrl, followAllRedirects: true },
      function (error, response) {
        if (error)
        {
          var error = "downloadUrl: " + shortUrl + "returned error:" + error;
          urlsCallback(new gutil.PluginError('test', error, {showStack: false}));
          process.exit(1);
          return;
        }
        var expandedUrl = response.request.href
        var matches = expandedUrl.match(/org\/elasticsearch\/distribution\/deb\/elasticsearch\/(.+)\/elasticsearch-(.+)\.deb/);
        if (!matches.length)
        {
          console.error("downloadUrl: " + shortUrl + " does not expand to a debian package but:" + expandedUrl);
          urlsCallback();
          process.exit(1);
          return;
        }
        if (matches[1] != v.version)
        {
          var error = "downloadUrl: " + shortUrl + " expands to a debian package but not to expected version:"+ v.version+" instead we saw:" + expandedUrl;
          urlsCallback(new gutil.PluginError('test', error, {showStack: false}));
          process.exit(1);
          return;
        }
        urlsCallback();
      });
  };
  urls.forEach(function (v) { expandUrl(v.url, v)});

});

gulp.task('bash-patch', [ "link-checker" ], function(cb){
  var elifs = 0;
  var branches = _.keys(allowedValues.versions)
    .filter(function(k) { return !!allowedValues.versions[k].downloadUrl })
    .map(function (k) {
      var v = allowedValues.versions[k];
      var command = (elifs == 0) ? "if" : "elif";
      elifs++;
      return  "    " + command +" [[ \"${ES_VERSION}\" == \"" + k + "\"]]; then\r\n      DOWNLOAD_URL=\"" +v.downloadUrl+ "\"\r\n";
    });
  var ifStatements = branches.join("")

  return gulp.src([installElasticsearchBash])
    .pipe(replace(/(\#begin telemetry.*)[\s\S]+(\#end telemetry.*)/g, "$1\r\n" + ifStatements + "    $2"))
    .pipe(gulp.dest("../src/scripts/", { overwrite: true }));
});
