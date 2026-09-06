import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const compose = await readFile(new URL('../my3d-foxforge/docker-compose.yml', import.meta.url), 'utf8');
const manifest = await readFile(new URL('../my3d-foxforge/umbrel-app.yml', import.meta.url), 'utf8');
const readme = await readFile(new URL('../my3d-foxforge/README.md', import.meta.url), 'utf8');
const packageContract = JSON.parse(
  await readFile(new URL('../my3d-foxforge/foxforge-package.json', import.meta.url), 'utf8'),
);

const sourceSha = 'c11f7145b4354aa79c8f0fad223648240e652bac';
const digest = 'sha256:75d656bafcafb4e0e566548f6cca941244d29fef1bbc5be98e425f375246056a';
const image = `ghcr.io/mikefox303/foxforge:sha-c11f714@${digest}`;
const packageVersion = '0.1.0-alpha.4.3-umbrel.4';

test('FoxForge package pins the exact Pre-Alpha 5 validation image', () => {
  assert.ok(compose.includes(`    image: ${image}\n`));
  assert.match(manifest, new RegExp(`^version: "${packageVersion.replaceAll('.', '\\.') }"$`, 'm'));
  assert.doesNotMatch(compose, /:latest(?:@|\s|$)/);
  assert.ok(manifest.includes(sourceSha));
  assert.ok(manifest.includes(digest));
  assert.match(manifest, /not the final|не финальный/i);
  assert.match(readme, /Pre-Alpha 5 physical-validation candidate/);
  assert.ok(readme.includes(sourceSha));
});

test('FoxForge validation package records a published base and explicit candidate source', () => {
  assert.equal(packageContract.packageRole, 'pre-alpha-5-validation-candidate');
  assert.equal(packageContract.baseReleaseVersion, '0.1.0-alpha.4.3');
  assert.equal(packageContract.targetReleaseVersion, '0.1.0-alpha.5');
  assert.equal(packageContract.sourceCommit, sourceSha);
  assert.equal(packageContract.imageDigest, digest);
  assert.match(manifest, /^version: "0\.1\.0-alpha\.4\.3-umbrel\.4"$/m);
  assert.match(readme, /package-local identity `0\.1\.0-alpha\.4\.3-umbrel\.4`/);
  assert.match(readme, /base remains tied to the latest published FoxForge release/);
  assert.match(readme, /must not be treated as the final Alpha 5 release/);
});

test('FoxForge candidate 4 preserves routing safety and adds operator-facing validation UX', () => {
  assert.match(readme, /Update Printer now performs the same test-before-save check/);
  assert.match(readme, /same-key retry replays the same safe error/);
  assert.match(readme, /compiler-owned toolhead decision/);
  assert.match(readme, /one native snapshot/);
  assert.match(readme, /project_file\.nozzle_mapping/);
  assert.match(readme, /real source IDs in `ams_mapping2`/);
  assert.match(readme, /does not auto-pick a spool/);
  assert.match(manifest, /fail-closed X2D material routing/);
  assert.match(manifest, /project_file nozzle_mapping/);
  assert.match(manifest, /External 254\/255/);
  assert.match(readme, /queue UI now inspects staged 3MF print plans/);
  assert.match(readme, /bounded server-visible RFC1918 subnets/);
  assert.match(readme, /typed Material Topology routes/);
  assert.match(readme, /390x844, 900x1024, 1920x1080 and 5120x1440/);
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
  assert.equal(packageContract.authMode, 'write-enabled');
  assert.equal(typeof packageContract.reason, 'string');
  assert.ok(packageContract.reason.length > 20);

  // ADR 0005 deliberately rejects tokenless trusted-browser mode in production.
  assert.doesNotMatch(compose, /FOXFORGE_TRUSTED_BROWSER_SESSIONS:\s*["']?(?:true|1|yes|on)["']?\s*$/im);

  assert.match(compose, /^\s*FOXFORGE_COMMAND_TOKEN:\s*["']?\$\{APP_PASSWORD\}["']?\s*$/m);
  assert.match(packageContract.reason, /APP_PASSWORD/);
  assert.match(readme, /Unlock writes/);
  assert.match(readme, /APP_PASSWORD/);
});

test('FoxForge persists app-owned state using umbrelOS-compatible short volume syntax', () => {
  assert.match(compose, /^      - \$\{APP_DATA_DIR\}\/data:\/data$/m);
  assert.doesNotMatch(compose, /^\s*-\s*type:\s*bind/m);
  assert.match(compose, /\/healthz/);
});

test('FoxForge setup guide documents current secret-store and guarded print workflow', () => {
  for (const expected of [
    '"adapterKind": "bambu"',
    '"host": "192.168.1.100"',
    '"adapterKind": "moonraker"',
    '"base_url": "http://192.168.1.120:7125"',
    'data/secrets.json',
    'Do not manually place credentials in `config.json`',
    'data/artifacts/',
    'press **Start** separately',
    '`INDETERMINATE`',
    'Pause/Resume/Cancel',
    '**Diagnostics**',
    '`ams_mapping` / `ams_mapping2` / `nozzle_mapping`',
  ]) {
    assert.ok(readme.includes(expected), `missing setup guidance: ${expected}`);
  }
  assert.doesNotMatch(readme, /"access_code"\s*:/);
  assert.doesNotMatch(readme, /"api_key"\s*:/);
});

test('physical validation checklist covers the real Pre-Alpha 5 acceptance path', () => {
  for (const expected of [
    'Raspberry Pi 5/Umbrel + X2D + AMS 2 Pro',
    'add the X2D through the GUI',
    'restart FoxForge',
    'temporarily make the X2D unreachable',
    'inspect its material requirements',
    'FTPS upload + MQTT `project_file` acknowledgement',
    '`ams_mapping`, `ams_mapping2` and `nozzle_mapping` evidence',
    'Pause, Resume and Cancel',
    'not retained in browser storage',
  ]) {
    assert.ok(readme.includes(expected), `missing physical validation step: ${expected}`);
  }
});
