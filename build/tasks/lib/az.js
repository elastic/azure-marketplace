const exec = require('child_process').exec;

function azExec(args, cb) {
  exec("az " + args.join(' '), cb);
}

module.exports = azExec;
