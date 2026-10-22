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
    `services:
  app_proxy:
    environment:
      APP_HOST: server
  server:
    image: ghcr.io/maziggy/bambuddy:1.2.5.5@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    cap_add:
      - NET_BIND_SERVICE
    environment:
      VIRTUAL_PRINTER_ADVERTISE_ADDRESS: 192.168.0.100
      VIRTUAL_PRINTER_PASV_ADDRESS: 192.168.0.100
    ports:
      - "21:21"
      - "8883:8883"
    networks:
      default:
        ipv4_address: 10.21.0.2
        gw_priority: 1
networks:
  default:
    external: true
    name: umbrel_main_network
`,
  );
  fs.writeFileSync(
    path.join(appDirectory, 'umbrel-app.yml'),
    'version: "1.2.5.5-official.1"\nreleaseNotes: >-\n  Previous notes.\n',
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

test('updates only the official Bambuddy image, version, and release notes', () => {
  withPackage((directory) => {
    runSync(directory, '1.2.5.6', validDigest);

    const compose = fs.readFileSync(path.join(directory, 'my3d-bambuddy/docker-compose.yml'), 'utf8');
    const manifest = fs.readFileSync(path.join(directory, 'my3d-bambuddy/umbrel-app.yml'), 'utf8');
    assert.match(compose, new RegExp(`ghcr.io/maziggy/bambuddy:1\\.2\\.5\\.6@${validDigest}`));
    assert.doesNotMatch(compose, /network_mode:\s*host/);
    assert.match(compose, /APP_HOST:\s*server/);
    assert.match(compose, /ipv4_address:\s*10\.21\.0\.2/);
    assert.match(compose, /name:\s*umbrel_main_network/);
    assert.match(compose, /VIRTUAL_PRINTER_ADVERTISE_ADDRESS:\s*192\.168\.0\.100/);
    assert.match(compose, /VIRTUAL_PRINTER_PASV_ADDRESS:\s*192\.168\.0\.100/);
    assert.match(compose, /"8883:8883"/);
    assert.match(compose, /NET_BIND_SERVICE/);
    assert.doesNotMatch(compose, /bambuddy_lan|bambuddy_bridge|192\.168\.0\.200|NET_ADMIN|post_start/);

    assert.match(manifest, /^version: "1\.2\.5\.6"$/m);
    assert.match(manifest, /Официальный upstream Bambuddy 1\.2\.5\.6/);
    assert.match(manifest, /Spoolman/);
  });
});

test('rejects mutable, prerelease, and downstream tags before touching package files', () => {
  for (const tag of ['latest', 'daily', '1.2.6b1', '1.2.5.5-x2d.204']) {
    withPackage((directory) => {
      assert.throws(
        () => runSync(directory, tag, validDigest),
        /Invalid stable Bambuddy version/,
      );
      const compose = fs.readFileSync(path.join(directory, 'my3d-bambuddy/docker-compose.yml'), 'utf8');
      assert.match(compose, /maziggy\/bambuddy:1\.2\.5\.5@sha256:a{64}/);
    });
  }
});

test('rejects invalid digests before touching package files', () => {
  withPackage((directory) => {
    assert.throws(
      () => runSync(directory, '1.2.5.6', 'sha256:not-a-digest'),
      /Invalid multi-architecture digest/,
    );
  });
});

test('fails loudly when the official image is absent', () => {
  withPackage((directory) => {
    fs.writeFileSync(path.join(directory, 'my3d-bambuddy/docker-compose.yml'), 'services: {}\n');
    assert.throws(
      () => runSync(directory, '1.2.5.6', validDigest),
      /Pinned official maziggy Bambuddy image reference was not found/,
    );
  });
});
