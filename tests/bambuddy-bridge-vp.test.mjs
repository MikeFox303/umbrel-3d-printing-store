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
  assert.match(compose, /^\s*ipv4_address:\s*10\.21\.250\.200\s*$/m);
  assert.match(compose, /^\s*name:\s*umbrel_main_network\s*$/m);
  assert.match(compose, /^\s*VIRTUAL_PRINTER_ADVERTISE_ADDRESS:\s*192\.168\.0\.100\s*$/m);
  assert.match(compose, /^\s*VIRTUAL_PRINTER_PASV_ADDRESS:\s*192\.168\.0\.100\s*$/m);
  assert.match(compose, /^\s*-\s*NET_BIND_SERVICE\s*$/m);

  for (const port of publishedPorts) {
    assert.ok(compose.includes(`"${port}"`), `missing published port ${port}`);
  }
});

test('static Virtual Printer address is outside the Docker dynamic allocation block', () => {
  const match = compose.match(/^\s*ipv4_address:\s*(\d{1,3}(?:\.\d{1,3}){3})\s*$/m);
  assert.ok(match, 'static ipv4_address is missing');

  const octets = match[1].split('.').map(Number);
  assert.deepEqual(octets.slice(0, 2), [10, 21], `unexpected Umbrel subnet: ${match[1]}`);
  // Docker hands out addresses from the bottom of umbrel_main_network
  // (10.21.0.0/16), so a static address in 10.21.0.0/24 can be stolen while
  // Bambuddy is stopped. Keep the static address in the top of the /16.
  assert.ok(
    octets[2] >= 200,
    `static IP ${match[1]} is too close to the dynamic allocation start`,
  );
  assert.ok(octets[3] >= 2 && octets[3] <= 254, `invalid static IP host: ${match[1]}`);
});
