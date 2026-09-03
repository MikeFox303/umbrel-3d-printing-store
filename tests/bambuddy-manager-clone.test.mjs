import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import test from 'node:test';

const shouldRun = process.env.CI === 'true' && fs.existsSync('/var/run/docker.sock');

test(
  'Bambuddy Manager recreation inherits new image defaults',
  { skip: shouldRun ? false : 'requires CI Docker daemon' },
  () => {
    execFileSync('python3', ['tests/manager_clone_smoke.py'], {
      stdio: 'inherit',
      env: process.env,
    });
  },
);
