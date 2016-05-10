var require = patchRequire(require);

exports.login = function (username, password) {
  casper.start().then(function() {
    this.open("https://portal.azure.com/", { headers: { 'Accept-Language': 'en-US,en;q=0.5' } });
  });

  casper.waitForUrl(/https:\/\/login.microsoftonline.com\/common\/oauth2\/authorize/);
  casper.waitForSelector('#cred_userid_inputtext');
  casper.then(function() {
      casper.sendKeys("#cred_userid_inputtext", azureUser);
      casper.thenClick("#cred_password_inputtext");
      casper.waitUntilVisible("#redirect_dots_animation", function()
      {
        casper.waitWhileVisible("#redirect_dots_animation", function()
        {
          casper.waitForUrl(/login\.srf/, function ()
          {
            casper.waitForSelector('[name=passwd]');
            casper.sendKeys("[name=passwd]", azurePassword);
          });
        }, function() { }, 20000);
      });
  });
  casper.thenEvaluate(function() {
    document.querySelector("form").submit();
  });
  casper.then(function()
  {
    casper.waitForSelector("a div.fxs-sidebar-icon", function ()
    {
      casper.viewport(1600, 950, function() { });
    }, function() { }, 20000);
  });
}
