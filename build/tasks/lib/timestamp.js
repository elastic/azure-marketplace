var dateFormat = require("dateformat");
if (!GLOBAL.timestamp)
{
  const timestamp = dateFormat(new Date(), "-yyyymmdd-HHMMss-Z").replace("+","-");
  GLOBAL.timestamp = timestamp;
}
module.exports = GLOBAL.timestamp;
