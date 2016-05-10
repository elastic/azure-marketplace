var azureUser = "";
var azurePassword = "";

var azureLogin = require('./lib/azure-login');
var uiBlade = require('./lib/ui-definition-blade');

//these are casperjs defaults but solidifying them here because
//we rely on the login served at this resolution
casper.options.viewportSize = {width: 400, height: 300};

var screenshot = function(name, done)
{
  casper.viewport(1600, 950);
  casper.wait(100); //viewport then() very flakey :(
  casper.capture(name + ".png");
  if (done) done();
}

var failures = 0;
casper.test.on("fail", function(failure) {
  screenshot("failure-" + (++failures))
});

casper.test.begin('Can login to azure portal', 2, function suite(test) {
    azureLogin.login(azureUser, azurePassword)

    casper.run(function() {
      test.assertTitle("Dashboard - Microsoft Azure");
      test.assertUrlMatch(/https:\/\/portal.azure.com/);
      screenshot("dashboard", function () { test.done(); });
    });
});

casper.test.begin('Can load development UI definition blade', 2, function suite(test) {
    uiBlade.loadDevelopmentUI()

    casper.run(function() {
      test.assertTitleMatch(/^Basics - Microsoft Azure/);
      test.assertUrlMatch(/https:\/\/portal.azure.com/);
      screenshot("development blade", function() { test.done(); });
    });
});
