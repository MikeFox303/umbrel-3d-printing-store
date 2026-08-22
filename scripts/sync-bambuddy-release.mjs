import fs from 'node:fs';

const [version, digest] = process.argv.slice(2);

if (!/^\d+\.\d+\.\d+(?:\.\d+)?-x2d\.\d+$/.test(version ?? '')) {
  throw new Error(`Invalid validated Bambuddy X2D version: ${version ?? '<missing>'}`);
}
if (!/^sha256:[0-9a-f]{64}$/.test(digest ?? '')) {
  throw new Error(`Invalid multi-architecture digest: ${digest ?? '<missing>'}`);
}

const composePath = 'my3d-bambuddy/docker-compose.yml';
const manifestPath = 'my3d-bambuddy/umbrel-app.yml';
const compose = fs.readFileSync(composePath, 'utf8');
const manifest = fs.readFileSync(manifestPath, 'utf8');
const imagePattern = /image: ghcr\.io\/mikefox303\/bambuddy:[^@\s]+@sha256:[0-9a-f]{64}/;

if (!imagePattern.test(compose)) {
  throw new Error('Validated MikeFox303 Bambuddy image reference was not found in docker-compose.yml');
}
if (!/^version: ".+"$/m.test(manifest)) {
  throw new Error('Bambuddy version field was not found in umbrel-app.yml');
}
if (!/releaseNotes: >-[\s\S]*$/m.test(manifest)) {
  throw new Error('Bambuddy release notes field was not found in umbrel-app.yml');
}

const nextCompose = compose.replace(
  imagePattern,
  `image: ghcr.io/mikefox303/bambuddy:${version}@${digest}`,
);
const nextManifest = manifest
  .replace(/^version: ".*"$/m, `version: "${version}"`)
  .replace(
    /releaseNotes: >-[\s\S]*$/m,
    `releaseNotes: >-\n  Проверенная X2D-сборка Bambuddy ${version}.\n  Сохранены Cloud Mode без обязательного Developer Mode, inventory-only и безопасный учёт расхода.`,
  );

if (nextCompose !== compose) fs.writeFileSync(composePath, nextCompose);
if (nextManifest !== manifest) fs.writeFileSync(manifestPath, nextManifest);
