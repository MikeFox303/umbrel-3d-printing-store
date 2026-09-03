import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const manifest = fs.readFileSync('my3d-bambuddy-manager/umbrel-app.yml', 'utf8');
const compose = fs.readFileSync('my3d-bambuddy-manager/docker-compose.yml', 'utf8');
const source = fs.readFileSync('my3d-bambuddy-manager/src/server.py', 'utf8');
const template = fs.readFileSync('my3d-bambuddy-manager/server.py.template', 'utf8');

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

test('Manager snapshot retention is explicit', () => {
  assert.match(compose, /MAX_SNAPSHOTS:\s*"12"/);
});
