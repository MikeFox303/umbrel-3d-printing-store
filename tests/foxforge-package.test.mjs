import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const compose = await readFile(new URL('../my3d-foxforge/docker-compose.yml', import.meta.url), 'utf8');
const manifest = await readFile(new URL('../my3d-foxforge/umbrel-app.yml', import.meta.url), 'utf8');
const readme = await readFile(new URL('../my3d-foxforge/README.md', import.meta.url), 'utf8');
const packageContract = JSON.parse(
  await readFile(new URL('../my3d-foxforge/foxforge-package.json', import.meta.url), 'utf8'),
);

const image = 'ghcr.io/mikefox303/foxforge:0.1.0-alpha.3@sha256:efab08cdbfa515d83b665a71c2b48642d530c4880ec0d7b85b5488a34e2acc94';

test('FoxForge package pins the released multi-arch image', () => {
  assert.ok(compose.includes(`    image: ${image}\n`));
  assert.match(manifest, /^version: "0\.1\.0-alpha\.3"$/m);
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

test('FoxForge package declares a truthful application auth capability', () => {
  assert.equal(packageContract.schemaVersion, 1);
  assert.ok(['read-only', 'write-enabled'].includes(packageContract.authMode));
  assert.equal(typeof packageContract.reason, 'string');
  assert.ok(packageContract.reason.length > 20);

  // ADR 0005 deliberately rejects tokenless trusted-browser mode in production.
  assert.doesNotMatch(compose, /FOXFORGE_TRUSTED_BROWSER_SESSIONS:\s*["']?(?:true|1|yes|on)["']?\s*$/im);

  if (packageContract.authMode === 'read-only') {
    assert.doesNotMatch(compose, /^\s*FOXFORGE_COMMAND_TOKEN:/m);
    assert.match(packageContract.reason, /read|write|token|bootstrap/i);
    return;
  }

  // A write-enabled package must explicitly supply the FoxForge application
  // credential. App Proxy authentication alone is defense in depth, not the
  // application principal.
  assert.match(compose, /^\s*FOXFORGE_COMMAND_TOKEN:\s*\S+/m);
});

test('FoxForge persists app-owned state using umbrelOS-compatible short volume syntax', () => {
  assert.match(compose, /^      - \$\{APP_DATA_DIR\}\/data:\/data$/m);
  assert.doesNotMatch(compose, /^\s*-\s*type:\s*bind/m);
  assert.match(compose, /\/healthz/);
});

test('FoxForge setup guide documents supported adapters, secrets and guarded print workflow', () => {
  for (const expected of [
    '"adapterKind": "bambu"',
    '"access_code": "YOUR_LAN_ACCESS_CODE"',
    '"adapterKind": "moonraker"',
    '"base_url": "http://192.168.1.120:7125"',
    'Stored access codes and API keys remain inside the FoxForge app data directory',
    'data/artifacts/',
    'press **Start** separately',
    '`INDETERMINATE`',
  ]) {
    assert.ok(readme.includes(expected), `missing setup guidance: ${expected}`);
  }
});
