import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

const scriptPath = path.resolve('scripts/sync-bambuddy-release.mjs');
const validDigest = 'sha256:c670164aaa3b0c5af715ca00e9745cdf3a4d7d337fc11d96fc85180371952698';

function withPackage(run) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'bambuddy-sync-'));
  const appDirectory = path.join(directory, 'my3d-bambuddy');
  fs.mkdirSync(appDirectory, { recursive: true });
  fs.writeFileSync(
    path.join(appDirectory, 'docker-compose.yml'),
    'services:\n  server:\n    image: ghcr.io/mikefox303/bambuddy:1.2.5.3-test.x2d-cloud.2@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n',
  );
  fs.writeFileSync(
    path.join(appDirectory, 'umbrel-app.yml'),
    'version: "1.2.5.6"\nreleaseNotes: >-\n  Previous notes.\n',
  );

  try {
    run(directory);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
}

function runSync(directory, ...arguments_) {
  return execFileSync(process.execPath, [scriptPath, ...arguments_], {
    cwd: directory,
    encoding: 'utf8',
    stdio: 'pipe',
  });
}

test('updates only the validated custom Bambuddy image, version, and release notes', () => {
  withPackage((directory) => {
    runSync(directory, '1.2.5.3-x2d.42', validDigest);

    const compose = fs.readFileSync(path.join(directory, 'my3d-bambuddy/docker-compose.yml'), 'utf8');
    const manifest = fs.readFileSync(path.join(directory, 'my3d-bambuddy/umbrel-app.yml'), 'utf8');
    assert.match(compose, new RegExp(`ghcr.io/mikefox303/bambuddy:1\\.2\\.5\\.3-x2d\\.42@${validDigest}`));
    assert.match(manifest, /^version: "1\.2\.5\.3-x2d\.42"$/m);
    assert.match(manifest, /Проверенная X2D-сборка Bambuddy 1\.2\.5\.3-x2d\.42\./);
    assert.match(manifest, /inventory-only/);
  });
});

test('rejects official or arbitrary tags before touching package files', () => {
  withPackage((directory) => {
    assert.throws(
      () => runSync(directory, '1.2.5.4', validDigest),
      /Invalid validated Bambuddy X2D version/,
    );

    const compose = fs.readFileSync(path.join(directory, 'my3d-bambuddy/docker-compose.yml'), 'utf8');
    assert.match(compose, /mikefox303\/bambuddy:1\.2\.5\.3-test\.x2d-cloud\.2@sha256:a{64}/);
  });
});

test('rejects invalid digests before touching package files', () => {
  withPackage((directory) => {
    assert.throws(
      () => runSync(directory, '1.2.5.3-x2d.42', 'sha256:not-a-digest'),
      /Invalid multi-architecture digest/,
    );
  });
});

test('fails loudly when the validated custom image is absent', () => {
  withPackage((directory) => {
    fs.writeFileSync(path.join(directory, 'my3d-bambuddy/docker-compose.yml'), 'services: {}\n');
    assert.throws(
      () => runSync(directory, '1.2.5.3-x2d.42', validDigest),
      /Validated MikeFox303 Bambuddy image reference was not found/,
    );
  });
});
