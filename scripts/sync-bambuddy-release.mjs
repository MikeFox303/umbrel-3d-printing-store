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
const channelPath = 'channels/bambuddy/stable.json';
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

const immutableImage = `ghcr.io/maziggy/bambuddy:${version}@${digest}`;
const nextCompose = compose.replace(imagePattern, `image: ${immutableImage}`);
const nextManifest = manifest
  .replace(/^version: ".*"$/m, `version: "${version}"`)
  .replace(
    /releaseNotes: >-[\s\S]*$/m,
    `releaseNotes: >-\n  Официальный upstream Bambuddy ${version}, закреплённый по immutable multi-arch digest.\n  FilaMan-specific fork code не используется runtime; Spoolman — рекомендуемый inventory backend.`,
  );

const channel = {
  schemaVersion: 1,
  channel: 'stable',
  version,
  releaseTag: `v${version}`,
  image: `ghcr.io/maziggy/bambuddy:${version}`,
  digest,
  immutableImage,
  source: 'github-release',
  testedPlatforms: ['linux/amd64', 'linux/arm64'],
  available: true,
};

if (nextCompose !== compose) fs.writeFileSync(composePath, nextCompose);
if (nextManifest !== manifest) fs.writeFileSync(manifestPath, nextManifest);
fs.mkdirSync('channels/bambuddy', { recursive: true });
fs.writeFileSync(channelPath, `${JSON.stringify(channel, null, 2)}\n`);
