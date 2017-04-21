var dateFormat = require("dateformat");
if (!global.timestamp)
{
  const timestamp = dateFormat(new Date(), "-yyyymmdd-HHMMss-Z").replace("+","-");
  global.timestamp = timestamp;
}
module.exports = global.timestamp;
