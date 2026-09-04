import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const compose = await readFile(new URL('../my3d-foxforge/docker-compose.yml', import.meta.url), 'utf8');
const manifest = await readFile(new URL('../my3d-foxforge/umbrel-app.yml', import.meta.url), 'utf8');
const readme = await readFile(new URL('../my3d-foxforge/README.md', import.meta.url), 'utf8');

const image = 'ghcr.io/mikefox303/foxforge:0.1.0-alpha.2@sha256:02ae9788ccf0412d11d97af607e13e9e9b39df51b1b6d50743ae333ef8cfedc1';

test('FoxForge package pins the released multi-arch image', () => {
  assert.ok(compose.includes(`    image: ${image}\n`));
  assert.match(manifest, /^version: "0\.1\.0-alpha\.2"$/m);
  assert.doesNotMatch(compose, /:latest(?:@|\s|$)/);
});

test('FoxForge uses authenticated Umbrel App Proxy without host privileges', () => {
  assert.match(compose, /^      APP_HOST: my3d-foxforge_server_1$/m);
  assert.match(compose, /^      APP_PORT: 8000$/m);
  assert.doesNotMatch(compose, /PROXY_AUTH_ADD:\s*["']?false/);
  assert.doesNotMatch(compose, /network_mode:\s*host/);
  assert.doesNotMatch(compose, /privileged:\s*true/);
  assert.doesNotMatch(compose, /docker\.sock/);
  assert.match(manifest, /^port: 8283$/m);
});

test('FoxForge persists app-owned state using umbrelOS-compatible short volume syntax', () => {
  assert.match(compose, /^      - \$\{APP_DATA_DIR\}\/data:\/data$/m);
  assert.doesNotMatch(compose, /^\s*-\s*type:\s*bind/m);
  assert.match(compose, /\/healthz/);
});

test('FoxForge setup guide documents both first alpha adapters and secret handling', () => {
  for (const expected of [
    '"adapterKind": "bambu"',
    '"access_code": "YOUR_LAN_ACCESS_CODE"',
    '"adapterKind": "moonraker"',
    '"base_url": "http://192.168.1.120:7125"',
    'Keep access codes and API keys private',
  ]) {
    assert.ok(readme.includes(expected), `missing setup guidance: ${expected}`);
  }
});
