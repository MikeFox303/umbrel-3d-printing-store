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

test('Manager package revision stays compatible with its runtime core line', () => {
  const manifestVersion = manifest.match(/^version: "([^"]+)"$/m)?.[1];
  const runtimeVersion = source.match(/^MANAGER_VERSION = "([^"]+)"$/m)?.[1];
  assert.ok(manifestVersion, 'Manager manifest version is missing');
  assert.ok(runtimeVersion, 'Manager runtime version is missing');

  const packageParts = manifestVersion.split('.').map(Number);
  const runtimeParts = runtimeVersion.split('.').map(Number);
  assert.equal(packageParts.length, 3, 'Manager package version must have three numeric components');
  assert.equal(runtimeParts.length, 3, 'Manager runtime version must have three numeric components');
  assert.ok(packageParts.every(Number.isInteger), 'Manager package version must be numeric');
  assert.ok(runtimeParts.every(Number.isInteger), 'Manager runtime version must be numeric');
  assert.deepEqual(packageParts.slice(0, 2), runtimeParts.slice(0, 2));
  assert.ok(
    packageParts[2] >= runtimeParts[2],
    `Manager package ${manifestVersion} must not trail runtime core ${runtimeVersion}`,
  );
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
  assert.match(compose, /\$\{APP_BAMBUDDY_APP_DIR\}:\/umbrel-app-data\/my3d-bambuddy(?:\n|$)/);
  assert.match(compose, /\$\{APP_BAMBUDDY_DATA_DIR\}:\/umbrel-app-data\/my3d-bambuddy\/data(?:\n|$)/);
  assert.doesNotMatch(compose, /create_host_path:/);
  assert.doesNotMatch(compose, /\/home\/umbrel\/umbrel\/app-data\/my3d-bambuddy/);
  assert.doesNotMatch(compose, /\/state\/default\/persist\/data\/.*my3d-bambuddy/);
});

test('Manager volumes stay compatible with umbrelOS 1.7.4 patchComposeFile', () => {
  const serverVolumesBlock = compose.match(/\n    volumes:\n([\s\S]*?)\n    tmpfs:/)?.[1];
  assert.ok(serverVolumesBlock, 'server volumes block is missing');

  const volumeEntries = [...serverVolumesBlock.matchAll(/^\s+-\s+(.+)$/gm)].map((match) => match[1]);
  assert.equal(volumeEntries.length, 5, 'Manager server must keep exactly five volume entries');
  assert.doesNotMatch(serverVolumesBlock, /^\s+-\s+type:/m);
  assert.doesNotMatch(serverVolumesBlock, /^\s+source:/m);
  assert.doesNotMatch(serverVolumesBlock, /^\s+target:/m);

  // umbrelOS 1.7.4 App.patchComposeFile() treats every volume entry as a string
  // and calls replace() twice. Object/long Compose volume syntax throws here
  // before app-script install is ever reached.
  for (const volume of volumeEntries) {
    assert.doesNotThrow(() =>
      volume
        .replace('/data/storage/downloads', '/home/Downloads')
        .replace('/data/storage', '/home'),
    );
  }
});

test('Manager has a path fallback for Bambuddy packages installed before dependency exports existed', () => {
  assert.match(managerExports, /if \[\[ -z "\$\{APP_BAMBUDDY_APP_DIR:-\}" \]\]/);
  assert.match(managerExports, /dirname "\$\{EXPORTS_APP_DIR\}"/);
  assert.match(managerExports, /\/my3d-bambuddy"/);
  assert.match(managerExports, /if \[\[ -z "\$\{APP_BAMBUDDY_DATA_DIR:-\}" \]\]/);
  assert.match(managerExports, /SCRIPT_APP_DATA_ROOTS/);
  assert.match(managerExports, /jq --exit-status --raw-output --arg app "my3d-bambuddy"/);
  assert.match(managerExports, /APP_BAMBUDDY_DATA_DIR="\$\{APP_BAMBUDDY_APP_DIR\}\/data"/);
  assert.doesNotMatch(managerExports, /\/home\/umbrel\/umbrel/);
  assert.doesNotMatch(managerExports, /\/state\/default\/persist/);

  const baseLegacyEnv = {
    ...process.env,
    EXPORTS_APP_DIR: '/srv/umbrel/app-data/my3d-bambuddy-manager',
    APP_BAMBUDDY_APP_DIR: '',
    APP_BAMBUDDY_DATA_DIR: '',
  };

  const legacy = spawnSync(
    'bash',
    ['-c', 'source my3d-bambuddy-manager/exports.sh; printf "%s\\n%s\\n" "$APP_BAMBUDDY_APP_DIR" "$APP_BAMBUDDY_DATA_DIR"'],
    {
      encoding: 'utf8',
      env: {...baseLegacyEnv, SCRIPT_APP_DATA_ROOTS: ''},
    },
  );
  assert.equal(legacy.status, 0, legacy.stderr);
  assert.deepEqual(legacy.stdout.trim().split('\n'), [
    '/srv/umbrel/app-data/my3d-bambuddy',
    '/srv/umbrel/app-data/my3d-bambuddy/data',
  ]);

  const legacyRelocated = spawnSync(
    'bash',
    ['-c', 'source my3d-bambuddy-manager/exports.sh; printf "%s\\n%s\\n" "$APP_BAMBUDDY_APP_DIR" "$APP_BAMBUDDY_DATA_DIR"'],
    {
      encoding: 'utf8',
      env: {
        ...baseLegacyEnv,
        SCRIPT_APP_DATA_ROOTS: JSON.stringify({
          'my3d-bambuddy': '/mnt/external/Apps/my3d-bambuddy/data',
          'my3d-bambuddy-manager': '/srv/umbrel/app-data/my3d-bambuddy-manager/data',
        }),
      },
    },
  );
  assert.equal(legacyRelocated.status, 0, legacyRelocated.stderr);
  assert.deepEqual(legacyRelocated.stdout.trim().split('\n'), [
    '/srv/umbrel/app-data/my3d-bambuddy',
    '/mnt/external/Apps/my3d-bambuddy/data',
  ]);

  const dependencyRelocated = spawnSync(
    'bash',
    ['-c', 'source my3d-bambuddy-manager/exports.sh; printf "%s\\n%s\\n" "$APP_BAMBUDDY_APP_DIR" "$APP_BAMBUDDY_DATA_DIR"'],
    {
      encoding: 'utf8',
      env: {
        ...process.env,
        EXPORTS_APP_DIR: '/srv/umbrel/app-data/my3d-bambuddy-manager',
        SCRIPT_APP_DATA_ROOTS: JSON.stringify({
          'my3d-bambuddy': '/mnt/runtime-map/should-not-win',
        }),
        APP_BAMBUDDY_APP_DIR: '/srv/umbrel/app-data/my3d-bambuddy',
        APP_BAMBUDDY_DATA_DIR: '/mnt/external/Apps/my3d-bambuddy/data',
      },
    },
  );
  assert.equal(dependencyRelocated.status, 0, dependencyRelocated.stderr);
  assert.deepEqual(dependencyRelocated.stdout.trim().split('\n'), [
    '/srv/umbrel/app-data/my3d-bambuddy',
    '/mnt/external/Apps/my3d-bambuddy/data',
  ]);
});

test('Manager snapshot retention is explicit', () => {
  assert.match(compose, /MAX_SNAPSHOTS:\s*"12"/);
});
