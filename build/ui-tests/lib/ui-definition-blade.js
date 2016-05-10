var require = patchRequire(require);
require("../waitForSelectorText")

var bladeLoadHost = "https://portal.azure.com/";
var bladePath = "#blade/Microsoft_Azure_Compute/CreateMultiVmWizardBlade/internal_bladeCallId/anything/internal_bladeCallerParams/";
var bladeUrl = bladeLoadHost
  + bladePath
  + "%7B%22initialData%22:%7B%7D,%22providerConfig%22:%7B%22createUiDefinition%22:%22"
  + "https%3A%2F%2Fraw.githubusercontent.com%2Felastic%2Fazure-marketplace%2Fmaster%2Fsrc%2FcreateUiDefinition.json%22%7D%7D"

exports.loadDevelopmentUI = function ()
{
  casper.start().then(function() {
    this.open(bladeUrl, { headers: { 'Accept-Language': 'en-US,en;q=0.5' } });
  });
  casper.then(function() {
    casper.waitForUrl(/^https:\/\/portal.azure.com\/$/, function() {
      casper.waitForSelector(".fxc-wizard-step", function()
      {
        casper.waitForSelectorText(".fxs-blade-title-titleText", "Basics", function() {
          casper.waitUntilVisible(".fxs-blade-title-titleText", function () {
            casper.waitWhileVisible(".fxs-blade-progress-translucent");
          });
        });
      });
    }, function() {}, 20000);
  })

}
