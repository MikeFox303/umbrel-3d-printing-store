import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const compose = await readFile(new URL('../my3d-foxforge/docker-compose.yml', import.meta.url), 'utf8');
const manifest = await readFile(new URL('../my3d-foxforge/umbrel-app.yml', import.meta.url), 'utf8');
const readme = await readFile(new URL('../my3d-foxforge/README.md', import.meta.url), 'utf8');

const image = 'ghcr.io/mikefox303/foxforge:0.1.0-alpha.1@sha256:f9bdb39893162df49e3a6eddfcdc10c3f950fbccaa4e3abb631711bd0605e54b';

test('FoxForge package pins the released multi-arch image', () => {
  assert.match(compose, new RegExp(`^    image: ${image.replace(/[.*+?^${}()|[\\]\\]/g, '\\$&')}$`, 'm'));
  assert.match(manifest, /^version: "0\.1\.0-alpha\.1"$/m);
  assert.doesNotMatch(compose, /:latest(?:@|\s|$)/);
});

test('FoxForge uses Umbrel App Proxy without host privileges', () => {
  assert.match(compose, /^      APP_HOST: my3d-foxforge_server_1$/m);
  assert.match(compose, /^      APP_PORT: 8000$/m);
  assert.match(compose, /^      PROXY_AUTH_ADD: "false"$/m);
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
