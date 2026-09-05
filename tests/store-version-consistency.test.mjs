import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

function read(path) {
  return readFileSync(path, 'utf8');
}

function manifestVersion(path) {
  const match = read(path).match(/^version:\s*"([^"]+)"\s*$/m);
  assert.ok(match, `version was not found in ${path}`);
  return match[1];
}

function imageTag(path, pattern) {
  const match = read(path).match(pattern);
  assert.ok(match, `expected image was not found in ${path}`);
  return match[1];
}

const foxforgePackage = JSON.parse(read('my3d-foxforge/foxforge-package.json'));

const packages = [
  {
    id: 'my3d-bambuddy',
    image: /image:\s+ghcr\.io\/maziggy\/bambuddy:([^@\s]+)@sha256:[0-9a-f]{64}/,
    expectedTag: (version) => version,
  },
  {
    id: 'my3d-printbuddy',
    image: /image:\s+docker\.io\/vmhomelabde\/printbuddy:v([^@\s]+)/,
    expectedTag: (version) => version.replace(/-umbrel\.\d+$/, ''),
  },
  {
    id: 'my3d-spoolman',
    image: /image:\s+ghcr\.io\/donkie\/spoolman:([^@\s]+)@sha256:[0-9a-f]{64}/,
    expectedTag: (version) => version.replace(/-umbrel\.\d+$/, ''),
  },
  {
    id: 'my3d-filaman',
    image: /image:\s+ghcr\.io\/mikefox303\/filaman-system:([^@\s]+)@sha256:[0-9a-f]{64}/,
    expectedTag: (version) => version,
  },
  {
    id: 'my3d-foxforge',
    image: /image:\s+ghcr\.io\/mikefox303\/foxforge:([^@\s]+)@sha256:[0-9a-f]{64}/,
    expectedTag: (version) => {
      if (foxforgePackage.packageRole === 'pre-alpha-5-validation-candidate') {
        assert.match(foxforgePackage.sourceCommit, /^[0-9a-f]{40}$/);
        return `sha-${foxforgePackage.sourceCommit.slice(0, 7)}`;
      }
      return version.replace(/-umbrel\.\d+$/, '');
    },
  },
];

for (const pkg of packages) {
  test(`${pkg.id} manifest version matches its runtime image identity`, () => {
    const manifest = manifestVersion(`${pkg.id}/umbrel-app.yml`);
    const tag = imageTag(`${pkg.id}/docker-compose.yml`, pkg.image);
    assert.equal(tag, pkg.expectedTag(manifest));
  });
}

test('store runtime packages do not use floating latest tags', () => {
  for (const pkg of packages) {
    const compose = read(`${pkg.id}/docker-compose.yml`);
    assert.doesNotMatch(compose, /image:\s+[^\s]+:(?:latest|daily)(?:@|\s|$)/i, pkg.id);
  }
});
