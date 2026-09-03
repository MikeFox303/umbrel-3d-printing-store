import fs from 'node:fs';

const [version, digest] = process.argv.slice(2);

if (!/^\d+\.\d+\.\d+b\d+-daily\.\d{8}$/.test(version ?? '')) {
  throw new Error(`Invalid Bambuddy daily beta version: ${version ?? '<missing>'}`);
}
if (!/^sha256:[0-9a-f]{64}$/.test(digest ?? '')) {
  throw new Error(`Invalid multi-architecture digest: ${digest ?? '<missing>'}`);
}

const channelPath = 'channels/bambuddy/beta.json';
const immutableImage = `ghcr.io/maziggy/bambuddy:daily@${digest}`;
const channel = {
  schemaVersion: 1,
  channel: 'beta',
  version,
  releaseTag: `v${version}`,
  image: 'ghcr.io/maziggy/bambuddy:daily',
  digest,
  immutableImage,
  source: 'github-prerelease+ghcr-daily',
  testedPlatforms: ['linux/amd64', 'linux/arm64'],
  available: true,
};

fs.mkdirSync('channels/bambuddy', { recursive: true });
fs.writeFileSync(channelPath, `${JSON.stringify(channel, null, 2)}\n`);
