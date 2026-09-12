const assert = require('node:assert/strict');
const http = require('node:http');
const { once } = require('node:events');
const { createApp } = require('./serv00-app.js');

async function check(env) {
  const commands = [];
  let pending;
  const app = createApp({ env, execute(command, options, callback) {
    assert(options.timeout > 0 && options.maxBuffer <= 1024 * 1024);
    commands.push(command);
    pending = callback;
  }});
  assert.equal(app.host, '127.0.0.1');
  app.server.listen(0, app.host);
  await once(app.server, 'listening');
  const request = (path, method = 'GET', token = '') => new Promise((resolve, reject) => {
    const req = http.request({ host: app.host, port: app.server.address().port, path, method,
      headers: token ? { Authorization: `Bearer ${token}` } : {} }, res => {
      let body = '';
      res.on('data', data => body += data);
      res.on('end', () => resolve({ status: res.statusCode, body }));
    });
    req.setTimeout(3000, () => req.destroy(new Error('HTTP test timeout')));
    req.on('error', reject);
    req.end();
  });
  async function waitPending() {
    const deadline = Date.now() + 2000;
    while (!pending) {
      if (Date.now() >= deadline) throw new Error('Management command was not invoked');
      await new Promise(resolve => setTimeout(resolve, 5));
    }
  }
  try {
    for (const path of ['/up', '/re', '/rp', '/jc']) {
      assert.equal((await request(path)).status, 403);
      assert.equal((await request(path, 'POST', 'wrong')).status, 403);
      assert.equal((await request(path + '?token=' + env.SBD_SERV00_ADMIN_TOKEN, 'POST')).status, 403);
    }
    assert.equal(commands.length, 0);
    assert.equal((await request('/health')).status, 200);
    if (!env.SBD_SERV00_ADMIN_TOKEN) return;
    const token = env.SBD_SERV00_ADMIN_TOKEN;
    assert.equal((await request('/re', 'GET', token)).status, 405);
    for (const path of ['/up', '/re', '/rp', '/jc']) {
      pending = undefined;
      const operation = request(path, path === '/jc' ? 'GET' : 'POST', token);
      await waitPending();
      assert.equal((await request('/rp', 'POST', token)).status, 409);
      assert.equal(await app.keepalive(), false);
      pending(null, 'synthetic output');
      assert.equal((await operation).status, 200);
    }
    assert.equal(commands.length, 4);
    pending = undefined;
    const failed = request('/re', 'POST', token);
    await waitPending();
    pending(new Error('synthetic secret'));
    const result = await failed;
    assert.equal(result.status, 500);
    assert(!result.body.includes('synthetic secret'));
    // A failed command releases the shared operation guard.
    const keepalive = app.keepalive();
    pending(null, '');
    assert.equal(await keepalive, true);
  } finally {
    app.server.closeAllConnections();
    await new Promise(resolve => app.server.close(resolve));
  }
}
(async () => {
  await check({});
  await check({ SBD_SERV00_ADMIN_TOKEN: 'synthetic-test-token-0123456789abcdef' });
  console.log('[OK] Serv00 auth, methods, concurrency, failure handling and loopback binding');
})().catch(error => { console.error(error); process.exitCode = 1; });
