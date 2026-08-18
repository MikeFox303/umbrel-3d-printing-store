import fs from 'node:fs';

const [tag, digest] = process.argv.slice(2);
if (!/^\d+\.\d+\.\d+-localized\.\d+$/.test(tag ?? '')) {
  throw new Error(`Invalid localized image tag: ${tag ?? '<missing>'}`);
}
if (!/^sha256:[0-9a-f]{64}$/.test(digest ?? '')) {
  throw new Error(`Invalid multi-architecture digest: ${digest ?? '<missing>'}`);
}

const composePath = 'my3d-filaman/docker-compose.yml';
const manifestPath = 'my3d-filaman/umbrel-app.yml';
const compose = fs.readFileSync(composePath, 'utf8');
const manifest = fs.readFileSync(manifestPath, 'utf8');

const imagePattern = /image: ghcr\.io\/mikefox303\/filaman-system(?:-ru)?:[^@\s]+@sha256:[0-9a-f]{64}/;
if (!imagePattern.test(compose)) throw new Error('Image reference was not found in docker-compose.yml');

const nextCompose = compose.replace(
  imagePattern,
  `image: ghcr.io/mikefox303/filaman-system:${tag}@${digest}`,
);
const nextManifest = manifest
  .replace(/^version: ".*"$/m, `version: "${tag}"`)
  .replace(
    /releaseNotes: >-[\s\S]*$/m,
    `releaseNotes: >-\n  Автоматическое обновление локализованной сборки FilaMan до ${tag}.\n  Сохранены русская и украинская локализации, UAH и данные приложения.`,
  );

if (nextCompose !== compose) fs.writeFileSync(composePath, nextCompose);
if (nextManifest !== manifest) fs.writeFileSync(manifestPath, nextManifest);
