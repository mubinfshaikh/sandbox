const http = require('http');
const os = require('os');
http.createServer((req, res) => {
  if (req.url === '/health') { res.writeHead(200); return res.end('ok'); }
  res.writeHead(200, {'Content-Type': 'text/plain'});
  res.end(`Hello from ${os.hostname()} (version ${process.env.APP_VERSION || 'dev'})\n`);
}).listen(3000, () => console.log('listening on 3000'));
