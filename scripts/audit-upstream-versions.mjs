import fs from 'node:fs';

const token = process.env.GITHUB_TOKEN ?? '';
const headers = {
  Accept: 'application/vnd.github+json',
  'X-GitHub-Api-Version': '2022-11-28',
  'User-Agent': 'umbrel-3d-printing-store-version-audit',
};
if (token) headers.Authorization = `Bearer ${token}`;

function readManifestVersion(path) {
  const content = fs.readFileSync(path, 'utf8');
  const match = content.match(/^version:\s*"([^"]+)"\s*$/m);
  if (!match) throw new Error(`Cannot read version from ${path}`);
  return match[1];
}

function readJson(path) {
  return JSON.parse(fs.readFileSync(path, 'utf8'));
}

async function github(path) {
  const response = await fetch(`https://api.github.com${path}`, { headers });
  if (!response.ok) {
    throw new Error(`GitHub API ${path} returned ${response.status}`);
  }
  return response.json();
}

function stripV(tag) {
  return String(tag).replace(/^v/, '');
}

function packageBase(version) {
  return version.replace(/-umbrel\.\d+$/, '');
}

function localizedBase(version) {
  return version.replace(/-localized\.\d+$/, '');
}

const results = [];
function record(name, local, upstream, mode = 'strict') {
  const ok = local === upstream;
  results.push({ name, local, upstream, mode, ok });
  const prefix = ok ? 'OK' : mode === 'warning' ? 'WARN' : 'STALE';
  console.log(`${prefix.padEnd(5)} ${name}: store=${local} upstream=${upstream}`);
}

const bambuddy = await github('/repos/maziggy/bambuddy/releases/latest');
record(
  'Bambuddy stable channel',
  readJson('channels/bambuddy/stable.json').releaseTag,
  bambuddy.tag_name,
);

const bambuddyReleases = await github('/repos/maziggy/bambuddy/releases?per_page=30');
const latestBambuddyBeta = bambuddyReleases.find((release) => release.prerelease && !release.draft);
if (!latestBambuddyBeta) throw new Error('No Bambuddy prerelease was found');
record(
  'Bambuddy beta channel',
  readJson('channels/bambuddy/beta.json').releaseTag,
  latestBambuddyBeta.tag_name,
);

const printbuddy = await github('/repos/vmhomelab/printbuddy/releases/latest');
record(
  'Printbuddy',
  packageBase(readManifestVersion('my3d-printbuddy/umbrel-app.yml')),
  stripV(printbuddy.tag_name),
);

const spoolman = await github('/repos/Donkie/Spoolman/releases/latest');
record(
  'Spoolman',
  packageBase(readManifestVersion('my3d-spoolman/umbrel-app.yml')),
  stripV(spoolman.tag_name),
);

const filaman = await github('/repos/Fire-Devils/filaman-system/releases/latest');
record(
  'FilaMan localized base',
  localizedBase(readManifestVersion('my3d-filaman/umbrel-app.yml')),
  stripV(filaman.tag_name),
  'warning',
);

const foxforgeReleases = await github('/repos/MikeFox303/FoxForge/releases?per_page=30');
const latestFoxForge = foxforgeReleases.find((release) => !release.draft);
if (!latestFoxForge) throw new Error('No FoxForge release was found');

const foxforgeManifestVersion = readManifestVersion('my3d-foxforge/umbrel-app.yml');
const foxforgePackage = readJson('my3d-foxforge/foxforge-package.json');
let foxforgeAuditedVersion = packageBase(foxforgeManifestVersion);
let foxforgeAuditNote = '';

if (foxforgePackage.packageRole === 'pre-alpha-5-validation-candidate') {
  for (const field of ['baseReleaseVersion', 'targetReleaseVersion', 'sourceCommit', 'imageDigest']) {
    if (typeof foxforgePackage[field] !== 'string' || foxforgePackage[field].length === 0) {
      throw new Error(`FoxForge validation candidate is missing ${field}`);
    }
  }
  if (!/^[0-9a-f]{40}$/.test(foxforgePackage.sourceCommit)) {
    throw new Error('FoxForge validation candidate sourceCommit must be a full commit SHA');
  }
  if (!/^sha256:[0-9a-f]{64}$/.test(foxforgePackage.imageDigest)) {
    throw new Error('FoxForge validation candidate imageDigest must be an immutable sha256 digest');
  }
  foxforgeAuditedVersion = foxforgePackage.baseReleaseVersion;
  foxforgeAuditNote = `FoxForge candidate package ${foxforgeManifestVersion} audits published base ${foxforgeAuditedVersion}; source=${foxforgePackage.sourceCommit} target=${foxforgePackage.targetReleaseVersion}`;
  console.log(`INFO  ${foxforgeAuditNote}`);
}

record(
  'FoxForge published base',
  foxforgeAuditedVersion,
  stripV(latestFoxForge.tag_name),
);

const summary = [
  '## Upstream version audit',
  '',
  '| App/channel | Store | Upstream | Result |',
  '| --- | --- | --- | --- |',
  ...results.map(({ name, local, upstream, mode, ok }) => {
    const result = ok ? 'Current' : mode === 'warning' ? 'Review localized fork' : 'Update required';
    return `| ${name} | \`${local}\` | \`${upstream}\` | ${result} |`;
  }),
  '',
  'Bambuddy Stable/Beta are audited through channel metadata rather than the Umbrel bootstrap package. This preserves the Manager architecture where runtime channels can advance without rewriting the installed package definition.',
  '',
  'FilaMan upstream drift is informational here because the localized fork has its own guarded merge, localization, migration and image-validation gates. The Store must never replace it with an unvalidated upstream image automatically.',
  ...(foxforgeAuditNote ? ['', foxforgeAuditNote] : []),
  '',
].join('\n');

if (process.env.GITHUB_STEP_SUMMARY) {
  fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, summary);
}

const strictFailures = results.filter((result) => !result.ok && result.mode === 'strict');
if (strictFailures.length > 0) {
  console.error(`\n${strictFailures.length} Store package/channel update(s) required.`);
  process.exitCode = 1;
}
