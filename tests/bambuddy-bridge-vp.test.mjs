import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const compose = fs.readFileSync('my3d-bambuddy/docker-compose.yml', 'utf8');

const publishedPorts = [
  '21:21',
  '322:322',
  '990:990',
  '3000:3000',
  '3002:3002',
  '6000:6000',
  '8883:8883',
  '2024-2026:2024-2026',
  '50000-50100:50000-50100',
];

test('Bambuddy uses bridge networking with published Virtual Printer ports', () => {
  assert.doesNotMatch(compose, /network_mode:\s*host/);
  assert.doesNotMatch(compose, /bambuddy_lan|bambuddy_bridge/);
  assert.doesNotMatch(compose, /192\.168\.0\.200/);
  assert.doesNotMatch(compose, /^\s*entrypoint:/m);
  assert.doesNotMatch(compose, /^\s*post_start:/m);
  assert.doesNotMatch(compose, /NET_ADMIN/);

  assert.match(compose, /^\s*APP_HOST:\s*server\s*$/m);
  assert.match(compose, /^\s*ipv4_address:\s*10\.21\.0\.2\s*$/m);
  assert.match(compose, /^\s*name:\s*umbrel_main_network\s*$/m);
  assert.match(compose, /^\s*VIRTUAL_PRINTER_ADVERTISE_ADDRESS:\s*192\.168\.0\.100\s*$/m);
  assert.match(compose, /^\s*VIRTUAL_PRINTER_PASV_ADDRESS:\s*192\.168\.0\.100\s*$/m);
  assert.match(compose, /^\s*-\s*NET_BIND_SERVICE\s*$/m);

  for (const port of publishedPorts) {
    assert.ok(compose.includes(`"${port}"`), `missing published port ${port}`);
  }
});
