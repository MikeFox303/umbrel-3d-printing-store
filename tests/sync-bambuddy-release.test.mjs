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
    'services:\n  server:\n    image: ghcr.io/maziggy/bambuddy:1.2.5.2@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n',
  );
  fs.writeFileSync(
    path.join(appDirectory, 'umbrel-app.yml'),
    'version: "1.2.5.2"\nreleaseNotes: >-\n  Previous notes.\n',
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

test('updates only the Bambuddy image, version, and release notes for a stable tag', () => {
  withPackage((directory) => {
    runSync(directory, '1.2.5.3', validDigest);

    const compose = fs.readFileSync(path.join(directory, 'my3d-bambuddy/docker-compose.yml'), 'utf8');
    const manifest = fs.readFileSync(path.join(directory, 'my3d-bambuddy/umbrel-app.yml'), 'utf8');
    assert.match(compose, new RegExp(`ghcr.io/maziggy/bambuddy:1\\.2\\.5\\.3@${validDigest}`));
    assert.match(manifest, /^version: "1\.2\.5\.3"$/m);
    assert.match(manifest, /Автоматическое обновление Bambuddy до 1\.2\.5\.3\./);
  });
});

test('rejects prerelease tags before touching package files', () => {
  withPackage((directory) => {
    assert.throws(
      () => runSync(directory, '1.2.5.3-beta.1', validDigest),
      /Invalid stable Bambuddy version/,
    );

    const compose = fs.readFileSync(path.join(directory, 'my3d-bambuddy/docker-compose.yml'), 'utf8');
    assert.match(compose, /bambuddy:1\.2\.5\.2@sha256:a{64}/);
  });
});

test('rejects invalid digests before touching package files', () => {
  withPackage((directory) => {
    assert.throws(
      () => runSync(directory, '1.2.5.3', 'sha256:not-a-digest'),
      /Invalid multi-architecture digest/,
    );
  });
});

test('fails loudly when the expected Bambuddy image is absent', () => {
  withPackage((directory) => {
    fs.writeFileSync(path.join(directory, 'my3d-bambuddy/docker-compose.yml'), 'services: {}\n');
    assert.throws(
      () => runSync(directory, '1.2.5.3', validDigest),
      /Bambuddy image reference was not found/,
    );
  });
});
