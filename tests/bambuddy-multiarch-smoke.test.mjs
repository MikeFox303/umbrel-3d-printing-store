import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import test from 'node:test';

const helperPath = 'scripts/smoke-bambuddy-multiarch.sh';
const betaWorkflowPath = '.github/workflows/sync-bambuddy-beta.yml';
const stableWorkflowPath = '.github/workflows/sync-bambuddy.yml';

test('multiarch smoke helper is valid shell and uses OCI child manifest digests', () => {
  execFileSync('bash', ['-n', helperPath]);
  const helper = fs.readFileSync(helperPath, 'utf8');

  assert.match(helper, /\.manifests\[\]/);
  assert.match(helper, /\.platform\.architecture == \$arch/);
  assert.match(helper, /platform_image="\$\{REPOSITORY\}@\$\{child_digest\}"/);
  assert.match(helper, /docker pull --platform "\$platform" "\$platform_image"/);
  assert.doesNotMatch(helper, /docker pull --platform "\$platform" "\$IMAGE"/);
});

test('stable and beta workflows share the child-manifest smoke helper', () => {
  for (const workflowPath of [betaWorkflowPath, stableWorkflowPath]) {
    const workflow = fs.readFileSync(workflowPath, 'utf8');
    assert.match(workflow, /bash scripts\/smoke-bambuddy-multiarch\.sh/);
    assert.match(workflow, /- 'scripts\/smoke-bambuddy-multiarch\.sh'/);
    assert.doesNotMatch(workflow, /docker pull --platform "\$platform" "\$IMAGE"/);
  }
});
