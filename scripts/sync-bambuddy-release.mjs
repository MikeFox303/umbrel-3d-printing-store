import fs from 'node:fs';

const [version, digest] = process.argv.slice(2);

if (!/^\d+\.\d+\.\d+(?:\.\d+)?$/.test(version ?? '')) {
  throw new Error(`Invalid stable Bambuddy version: ${version ?? '<missing>'}`);
}
if (!/^sha256:[0-9a-f]{64}$/.test(digest ?? '')) {
  throw new Error(`Invalid multi-architecture digest: ${digest ?? '<missing>'}`);
}

const composePath = 'my3d-bambuddy/docker-compose.yml';
const manifestPath = 'my3d-bambuddy/umbrel-app.yml';
const compose = fs.readFileSync(composePath, 'utf8');
const manifest = fs.readFileSync(manifestPath, 'utf8');
const imagePattern = /image: ghcr\.io\/maziggy\/bambuddy:[^@\s]+@sha256:[0-9a-f]{64}/;

if (!imagePattern.test(compose)) {
  throw new Error('Pinned official maziggy Bambuddy image reference was not found in docker-compose.yml');
}
if (!/^version: ".+"$/m.test(manifest)) {
  throw new Error('Bambuddy version field was not found in umbrel-app.yml');
}
if (!/releaseNotes: >-[\s\S]*$/m.test(manifest)) {
  throw new Error('Bambuddy release notes field was not found in umbrel-app.yml');
}

const nextCompose = compose.replace(
  imagePattern,
  `image: ghcr.io/maziggy/bambuddy:${version}@${digest}`,
);
const nextManifest = manifest
  .replace(/^version: ".*"$/m, `version: "${version}"`)
  .replace(
    /releaseNotes: >-[\s\S]*$/m,
    `releaseNotes: >-\n  Официальный upstream Bambuddy ${version}, закреплённый по immutable multi-arch digest.\n  FilaMan-specific fork code не используется runtime; Spoolman — рекомендуемый inventory backend.`,
  );

if (nextCompose !== compose) fs.writeFileSync(composePath, nextCompose);
if (nextManifest !== manifest) fs.writeFileSync(manifestPath, nextManifest);
