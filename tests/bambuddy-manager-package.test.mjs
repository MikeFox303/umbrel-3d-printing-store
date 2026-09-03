import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import test from 'node:test';

const manifest = fs.readFileSync('my3d-bambuddy-manager/umbrel-app.yml', 'utf8');
const compose = fs.readFileSync('my3d-bambuddy-manager/docker-compose.yml', 'utf8');
const source = fs.readFileSync('my3d-bambuddy-manager/src/server.py', 'utf8');
const template = fs.readFileSync('my3d-bambuddy-manager/server.py.template', 'utf8');
const bambuddyExports = fs.readFileSync('my3d-bambuddy/exports.sh', 'utf8');
const managerExports = fs.readFileSync('my3d-bambuddy-manager/exports.sh', 'utf8');

test('Manager manifest and runtime versions match', () => {
  const manifestVersion = manifest.match(/^version: "([^"]+)"$/m)?.[1];
  const runtimeVersion = source.match(/^MANAGER_VERSION = "([^"]+)"$/m)?.[1];
  assert.ok(manifestVersion, 'Manager manifest version is missing');
  assert.ok(runtimeVersion, 'Manager runtime version is missing');
  assert.equal(runtimeVersion, manifestVersion);
});

test('Manager source and shipped template stay byte-for-byte equal', () => {
  assert.equal(template, source);
});

test('Manager requires Bambuddy and keeps Docker authority isolated', () => {
  assert.match(manifest, /dependencies:\n\s+- my3d-bambuddy(?:\n|$)/);
  assert.match(compose, /\/var\/run\/docker\.sock:\/var\/run\/docker\.sock/);
  assert.doesNotMatch(compose, /PROXY_AUTH_ADD:\s*["']?false/);
});

test('Manager resolves Bambuddy definition and persistent data through dependency exports', () => {
  assert.match(bambuddyExports, /export APP_BAMBUDDY_APP_DIR="\$\{EXPORTS_APP_DIR\}"/);
  assert.match(bambuddyExports, /export APP_BAMBUDDY_DATA_DIR="\$\{EXPORTS_APP_DATA_DIR\}"/);
  assert.match(compose, /\$\{APP_BAMBUDDY_APP_DIR\}:\/umbrel-app-data\/my3d-bambuddy/);
  assert.match(compose, /\$\{APP_BAMBUDDY_DATA_DIR\}:\/umbrel-app-data\/my3d-bambuddy\/data/);
  assert.doesNotMatch(compose, /\/home\/umbrel\/umbrel\/app-data\/my3d-bambuddy/);
  assert.doesNotMatch(compose, /\/state\/default\/persist\/data\/.*my3d-bambuddy/);
});

test('Manager has a path fallback for Bambuddy packages installed before dependency exports existed', () => {
  assert.match(managerExports, /if \[\[ -z "\$\{APP_BAMBUDDY_APP_DIR:-\}" \]\]/);
  assert.match(managerExports, /dirname "\$\{EXPORTS_APP_DIR\}"/);
  assert.match(managerExports, /\/my3d-bambuddy"/);
  assert.match(managerExports, /if \[\[ -z "\$\{APP_BAMBUDDY_DATA_DIR:-\}" \]\]/);
  assert.match(managerExports, /APP_BAMBUDDY_DATA_DIR="\$\{APP_BAMBUDDY_APP_DIR\}\/data"/);
  assert.doesNotMatch(managerExports, /\/home\/umbrel\/umbrel/);
  assert.doesNotMatch(managerExports, /\/state\/default\/persist/);

  const legacy = spawnSync(
    'bash',
    ['-c', 'source my3d-bambuddy-manager/exports.sh; printf "%s\\n%s\\n" "$APP_BAMBUDDY_APP_DIR" "$APP_BAMBUDDY_DATA_DIR"'],
    {
      encoding: 'utf8',
      env: {...process.env, EXPORTS_APP_DIR: '/srv/umbrel/app-data/my3d-bambuddy-manager'},
    },
  );
  assert.equal(legacy.status, 0, legacy.stderr);
  assert.deepEqual(legacy.stdout.trim().split('\n'), [
    '/srv/umbrel/app-data/my3d-bambuddy',
    '/srv/umbrel/app-data/my3d-bambuddy/data',
  ]);

  const relocated = spawnSync(
    'bash',
    ['-c', 'source my3d-bambuddy-manager/exports.sh; printf "%s\\n%s\\n" "$APP_BAMBUDDY_APP_DIR" "$APP_BAMBUDDY_DATA_DIR"'],
    {
      encoding: 'utf8',
      env: {
        ...process.env,
        EXPORTS_APP_DIR: '/srv/umbrel/app-data/my3d-bambuddy-manager',
        APP_BAMBUDDY_APP_DIR: '/srv/umbrel/app-data/my3d-bambuddy',
        APP_BAMBUDDY_DATA_DIR: '/mnt/external/Apps/my3d-bambuddy/data',
      },
    },
  );
  assert.equal(relocated.status, 0, relocated.stderr);
  assert.deepEqual(relocated.stdout.trim().split('\n'), [
    '/srv/umbrel/app-data/my3d-bambuddy',
    '/mnt/external/Apps/my3d-bambuddy/data',
  ]);
});

test('Manager snapshot retention is explicit', () => {
  assert.match(compose, /MAX_SNAPSHOTS:\s*"12"/);
});
