import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const compose = await readFile(new URL('../my3d-foxforge/docker-compose.yml', import.meta.url), 'utf8');
const manifest = await readFile(new URL('../my3d-foxforge/umbrel-app.yml', import.meta.url), 'utf8');
const readme = await readFile(new URL('../my3d-foxforge/README.md', import.meta.url), 'utf8');
const packageContract = JSON.parse(
  await readFile(new URL('../my3d-foxforge/foxforge-package.json', import.meta.url), 'utf8'),
);

const sourceSha = '78ace6f7b7412aa0d3fc58bed095aecdf9920f94';
const digest = 'sha256:b01f1d44199a4413167ee2369c0dfbcafa602312442772d27de18e04c24ed0eb';
const imageTag = 'ghcr.io/mikefox303/foxforge:sha-78ace6f';
const image = `${imageTag}@${digest}`;
const packageVersion = '0.1.0-alpha.4.3-umbrel.6';

const regexEscape = (value) => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

test('FoxForge package pins the exact Candidate 6 immutable image', () => {
  assert.ok(compose.includes(`    image: ${image}\n`));
  assert.match(manifest, new RegExp(`^version: "${regexEscape(packageVersion)}"$`, 'm'));
  assert.doesNotMatch(compose, /:latest(?:@|\s|$)/);
  assert.ok(manifest.includes(sourceSha));
  assert.ok(manifest.includes(digest));
  assert.ok(manifest.includes('Candidate 6'));
  assert.match(manifest, /not the final|не финальный/i);
  assert.match(readme, /Pre-Alpha 5 physical-validation Candidate 6/);
  assert.ok(readme.includes(sourceSha));
  assert.ok(readme.includes(digest));
  assert.ok(readme.includes(imageTag));
});

test('Candidate 6 contract records one explicit package/source/accounting identity', () => {
  assert.equal(packageContract.schemaVersion, 1);
  assert.equal(packageContract.packageRole, 'pre-alpha-5-validation-candidate');
  assert.equal(packageContract.packageVersion, packageVersion);
  assert.equal(packageContract.baseReleaseVersion, '0.1.0-alpha.4.3');
  assert.equal(packageContract.targetReleaseVersion, '0.1.0-alpha.5');
  assert.equal(packageContract.sourceCommit, sourceSha);
  assert.equal(packageContract.imageDigest, digest);
  assert.equal(packageContract.filamentAccountingMode, 'bambu-validation');
  assert.match(readme, /Candidate 5 is historical/);
  assert.match(readme, /Candidate 1–5 physical evidence must not be relabeled/);
  assert.match(readme, /semantic target: `v0\.1\.0-alpha\.5` — still unpublished/);
});

test('Candidate 6 carries the staged Bambu routing and capability-driven UI contract', () => {
  for (const expected of [
    'Provider → Connection → Identity → Verify',
    'Update Printer',
    'capability-driven application shell',
    'typed Material Topology',
    'Bambu thermal telemetry',
    'TOOLHEAD_METADATA_INVALID',
    'project_file.nozzle_mapping',
    'real IDs in `ams_mapping2`',
    'compiler-owned toolhead routing',
    'never auto-picks a spool',
    'never guesses a left/right nozzle',
  ]) {
    assert.ok(readme.includes(expected), `missing Candidate 6 contract text: ${expected}`);
  }

  assert.match(manifest, /staged Add Printer/);
  assert.match(manifest, /Material Topology/);
  assert.match(manifest, /thermal telemetry/);
  assert.match(manifest, /fail-closed compiler-owned 3MF routing/);
  assert.match(manifest, /AMS\/external source handling/);
});

test('Candidate 6 enables only the Bambu physical-validation accounting gate', () => {
  assert.match(compose, /^\s*FOXFORGE_FILAMENT_ACCOUNTING_MODE:\s*bambu-validation\s*$/m);
  assert.equal(packageContract.filamentAccountingMode, 'bambu-validation');
  assert.match(packageContract.reason, /Bambu-only physical-validation accounting gate/);

  for (const expected of [
    'generic FoxForge runtime default remains `FOXFORGE_FILAMENT_ACCOUNTING_MODE=disabled`',
    'automatic pre-dispatch accounting enforcement applies only to printers whose adapter kind is `bambu`',
    'Moonraker/Klipper and unknown/future providers remain outside this automatic enforcement mode',
    'does not infer consumed grams from print progress or vendor telemetry',
    'confirmed completion settles the reserved estimate exactly once',
    'require explicit actual-mass reconciliation',
    '`INDETERMINATE` outcomes keep reservations held',
    'accounting does not choose the physical source or toolhead',
  ]) {
    assert.ok(readme.includes(expected), `missing accounting safety statement: ${expected}`);
  }

  assert.match(manifest, /Bambu-only physical-validation/);
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

test('FoxForge package declares truthful application write authentication', () => {
  assert.equal(packageContract.authMode, 'write-enabled');
  assert.equal(typeof packageContract.reason, 'string');
  assert.ok(packageContract.reason.length > 20);

  // ADR 0005 deliberately rejects tokenless trusted-browser mode in production.
  assert.doesNotMatch(compose, /FOXFORGE_TRUSTED_BROWSER_SESSIONS:\s*["']?(?:true|1|yes|on)["']?\s*$/im);
  assert.match(compose, /^\s*FOXFORGE_COMMAND_TOKEN:\s*["']?\$\{APP_PASSWORD\}["']?\s*$/m);
  assert.match(packageContract.reason, /explicit FoxForge write authentication/);
  assert.match(readme, /APP_PASSWORD → FOXFORGE_COMMAND_TOKEN/);
  assert.match(readme, /Unlock writes/);
  assert.match(readme, /app password shown by Umbrel/i);
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
    'explicit filament plan/reservation',
  ]) {
    assert.ok(readme.includes(expected), `missing setup guidance: ${expected}`);
  }
  assert.doesNotMatch(readme, /"access_code"\s*:/);
  assert.doesNotMatch(readme, /"api_key"\s*:/);
});

test('Candidate 6 physical checklist covers the real X2D/AMS2Pro acceptance fixture', () => {
  for (const expected of [
    'Raspberry Pi 5/Umbrel + X2D + AMS 2 Pro',
    'package `0.1.0-alpha.4.3-umbrel.6`',
    'add the X2D through the staged GUI wizard',
    'Bambu thermal telemetry',
    'AMS 2 Pro A1–A4 loaded with PETG',
    'External Left empty',
    'External Right loaded with PLA',
    'restart FoxForge',
    'temporarily make the X2D unreachable',
    'measured starting mass',
    'create the explicit accounting plan',
    'corrupt or ambiguous selected-plate toolhead metadata remains blocked',
    'FTPS upload + MQTT `project_file` acknowledgement',
    '`ams_mapping`, `ams_mapping2` and `nozzle_mapping` evidence',
    'weigh/measure the relevant spool',
    'explicit reconciliation is required',
  ]) {
    assert.ok(readme.includes(expected), `missing Candidate 6 physical validation step: ${expected}`);
  }
});
