var fs = require('fs');
  
function readFiles(dirname, filter, onFileContent, onError) {
  var filenames = fs.readdirSync(dirname);
  filenames.forEach((filename) => {
    if (fs.statSync(dirname + '/' + filename).isDirectory()) {
      readFiles(dirname + '/' + filename + '/', filter, onFileContent, onError);
    }
    else {
      if (filter(filename)) {
        var content = fs.readFileSync(dirname + filename, 'utf-8');
        onFileContent(dirname + filename, content);
      }
    }
  });
}

module.exports = { 
  readFiles: readFiles
};