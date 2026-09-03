import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const stableWorkflow = fs.readFileSync('.github/workflows/sync-bambuddy.yml', 'utf8');
const betaWorkflow = fs.readFileSync('.github/workflows/sync-bambuddy-beta.yml', 'utf8');
const multiarchSmoke = fs.readFileSync('scripts/smoke-bambuddy-multiarch.sh', 'utf8');

test('stable automation publishes channel metadata without mutating the Umbrel package', () => {
  assert.match(stableWorkflow, /node scripts\/sync-bambuddy-stable\.mjs/);
  assert.doesNotMatch(stableWorkflow, /node scripts\/sync-bambuddy-release\.mjs/);
  assert.doesNotMatch(stableWorkflow, /git add[^\n]*my3d-bambuddy\/(?:docker-compose\.yml|umbrel-app\.yml)/);
  assert.match(stableWorkflow, /git add channels\/bambuddy\/stable\.json/);
});

test('beta automation only publishes beta channel metadata', () => {
  assert.match(betaWorkflow, /node scripts\/sync-bambuddy-beta\.mjs/);
  assert.doesNotMatch(betaWorkflow, /sync-bambuddy-release\.mjs/);
  assert.doesNotMatch(betaWorkflow, /git add[^\n]*my3d-bambuddy\/(?:docker-compose\.yml|umbrel-app\.yml)/);
  assert.match(betaWorkflow, /git add channels\/bambuddy\/beta\.json/);
});

test('both channel workflows delegate multiarch runtime validation before publication', () => {
  for (const workflow of [stableWorkflow, betaWorkflow]) {
    assert.match(workflow, /bash scripts\/smoke-bambuddy-multiarch\.sh/);
    assert.match(workflow, /EXPECTED_APP_VERSION/);
    assert.match(workflow, /Revalidate .* after smoke tests/);
  }

  assert.match(multiarchSmoke, /linux\/amd64 linux\/arm64/);
  assert.match(multiarchSmoke, /\.platform\.architecture == \$arch/);
  assert.match(multiarchSmoke, /platform_image="\$\{REPOSITORY\}@\$\{child_digest\}"/);
  assert.match(multiarchSmoke, /APP_VERSION/);
});
