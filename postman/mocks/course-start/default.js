const http = require('http');

http.createServer((request, response) => {
  if (request.method !== 'POST' ||
      !/^\/api\/v1\/runs\/sessions\/[^/]+\/course\/start$/.test(request.url)) {
    response.writeHead(501).end();
    return;
  }
  if (!request.body?.startedAt || !Number.isFinite(Date.parse(request.body.startedAt))) {
    response.writeHead(400).end();
    return;
  }
  setTimeout(() => {
    response.writeHead(200, {'content-type': 'application/json'});
    response.end(JSON.stringify({result: 'SUCCESS', data: null}));
  }, 6000);
}).listen(process.env.PORT);
