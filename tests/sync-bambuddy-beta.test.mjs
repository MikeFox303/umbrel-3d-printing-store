import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

const scriptPath = path.resolve('scripts/sync-bambuddy-beta.mjs');
const validDigest = 'sha256:c670164aaa3b0c5af715ca00e9745cdf3a4d7d337fc11d96fc85180371952698';

function withPackage(run) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'bambuddy-beta-sync-'));
  fs.mkdirSync(path.join(directory, 'channels', 'bambuddy'), { recursive: true });
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

test('writes an immutable daily beta channel descriptor', () => {
  withPackage((directory) => {
    runSync(directory, '1.2.6b1-daily.20260830', validDigest);
    const channel = JSON.parse(
      fs.readFileSync(path.join(directory, 'channels/bambuddy/beta.json'), 'utf8'),
    );
    assert.equal(channel.channel, 'beta');
    assert.equal(channel.version, '1.2.6b1-daily.20260830');
    assert.equal(channel.image, 'ghcr.io/maziggy/bambuddy:daily');
    assert.equal(channel.digest, validDigest);
    assert.equal(channel.immutableImage, `ghcr.io/maziggy/bambuddy:daily@${validDigest}`);
    assert.equal(channel.available, true);
    assert.deepEqual(channel.testedPlatforms, ['linux/amd64', 'linux/arm64']);
  });
});

test('rejects stable, mutable-only and malformed version identifiers', () => {
  for (const version of ['1.2.5.5', 'daily', '1.2.6b1', '1.2.6b1-daily.2026-08-30']) {
    withPackage((directory) => {
      assert.throws(
        () => runSync(directory, version, validDigest),
        /Invalid Bambuddy daily beta version/,
      );
    });
  }
});

test('rejects invalid digests', () => {
  withPackage((directory) => {
    assert.throws(
      () => runSync(directory, '1.2.6b1-daily.20260830', 'sha256:not-a-digest'),
      /Invalid multi-architecture digest/,
    );
  });
});
