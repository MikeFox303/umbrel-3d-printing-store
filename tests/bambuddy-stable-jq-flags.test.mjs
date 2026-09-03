import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const workflow = fs.readFileSync('.github/workflows/sync-bambuddy.yml', 'utf8');

test('stable workflow does not use jq -e when extracting false boolean flags', () => {
  assert.doesNotMatch(workflow, /jq -er '\.(?:draft|prerelease)'/);
  assert.match(workflow, /draft="\$\(jq -r '\.draft'/);
  assert.match(workflow, /prerelease="\$\(jq -r '\.prerelease'/);
  assert.match(workflow, /latest_draft="\$\(jq -r '\.draft'/);
  assert.match(workflow, /latest_prerelease="\$\(jq -r '\.prerelease'/);
});

test('stable release JSON shape is validated before extraction', () => {
  const shapeCheck = /\.tag_name \| type == "string"[\s\S]*\.draft \| type == "boolean"[\s\S]*\.prerelease \| type == "boolean"/;
  assert.match(workflow, shapeCheck);
});
