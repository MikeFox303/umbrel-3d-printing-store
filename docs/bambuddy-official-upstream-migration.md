# Bambuddy official upstream migration

Date: 2026-09-03

Status: **release candidate only — keep PR draft until real X2D + Virtual Printer + Spoolman accounting acceptance passes**.

## Goal

Move the Umbrel Bambuddy runtime from the downstream `MikeFox303/bambuddy` fork to the official `maziggy/bambuddy v1.2.5.5` image while preserving the working X2D Virtual Printer network setup and using Spoolman as the authoritative inventory/accounting backend.

## Selected official runtime

```text
VERSION=1.2.5.5
IMAGE=ghcr.io/maziggy/bambuddy:1.2.5.5@sha256:dc627d618cc3d3252ae4ab33af74c4679c66a9a06e0e3bbb7aefa32d1a4d4a07
```

Observed platform manifests during the migration audit:

```text
linux/amd64 sha256:d6a29fa4d379957d7dec39984ca495e97e367f9010ec482795fb491d8a33a381
linux/arm64 sha256:e6ebd1f258d3588490f03b9d60da865414d86b5d1ac21de866d6303ea2c3c271
```

The Store consumes the official multi-arch image directly. It does not rebuild Bambuddy under the `MikeFox303` namespace.

## Actual live rollback baseline

The Raspberry Pi inspection superseded the earlier repository-only assumption about the installed fork version.

The real working runtime observed on the device is:

```text
IMAGE=ghcr.io/mikefox303/bambuddy:1.2.5.5-x2d.73@sha256:9abf0d5bfb612dd1f473a7632f2b7aa404ef06db759e979b388bd7466cc84fb0
NETWORK=host
APP_HOST=192.168.0.100
X2D_IP=192.168.0.151
```

This exact image is the physical rollback target for this acceptance run.

## Required Virtual Printer networking

`network_mode: host` is intentional and must remain.

The host mode was created for Virtual Printer and is part of the working configuration, not a temporary migration artifact.

Required RC invariants:

```yaml
app_proxy:
  environment:
    APP_HOST: 192.168.0.100
    APP_PORT: 8000

server:
  network_mode: host
  cap_add:
    - NET_BIND_SERVICE
  environment:
    VIRTUAL_PRINTER_ADVERTISE_ADDRESS: 192.168.0.100
    VIRTUAL_PRINTER_PASV_ADDRESS: 192.168.0.100
```

Do not change as part of this migration:

- `network_mode: host`;
- Raspberry Pi host IP `192.168.0.100`;
- X2D IP `192.168.0.151`;
- current LAN Only / Developer Mode state;
- Virtual Printer advertise/PASV addressing;
- Umbrel host routing;
- X2D MQTT/FTPS/camera routing.

The official Bambuddy `v1.2.5.5` Docker Compose itself supports Linux host mode, `NET_BIND_SERVICE`, and the `VIRTUAL_PRINTER_ADVERTISE_ADDRESS` / `VIRTUAL_PRINTER_PASV_ADDRESS` variables.

## Runtime change policy

For the live RC, the installed compose must remain byte-for-byte equivalent except for the Bambuddy image reference.

Expected change:

```text
FROM:
ghcr.io/mikefox303/bambuddy:1.2.5.5-x2d.73@sha256:9abf0d5bfb612dd1f473a7632f2b7aa404ef06db759e979b388bd7466cc84fb0

TO:
ghcr.io/maziggy/bambuddy:1.2.5.5@sha256:dc627d618cc3d3252ae4ab33af74c4679c66a9a06e0e3bbb7aefa32d1a4d4a07
```

The live migration helper `scripts/bambuddy-live-rc.sh` enforces this single-image-difference rule before restarting through Umbrel.

## Downstream fork disposition

### Consume upstream directly

Official upstream already owns the normal Bambuddy features required by this migration, including X2D/dual-nozzle handling, printer telemetry, FTPS/camera support, AMS handling, Spoolman assignments and usage tracking.

### Do not carry FilaMan-only runtime code

Do not reapply downstream code whose purpose was the FilaMan integration, including:

- FilaMan usage API routes;
- FilaMan durable replay ledger;
- FilaMan inventory-only assignment policy;
- FilaMan reconciliation;
- FilaMan-specific aggregate usage fallback;
- fork startup wiring whose only purpose is to install the above.

Spoolman is the intended inventory/accounting owner after migration.

### Keep Store/release safeguards

Retain in `umbrel-3d-printing-store`:

- immutable digest pinning;
- amd64/arm64 runtime smoke tests;
- anonymous image pull checks;
- compose validation;
- shadow DB migration preflight;
- exact physical rollback baseline;
- live RC helper with backup and automatic rollback;
- read-only upstream stable checking;
- no direct auto-publishing to `main`.

### RU/UK localization

Localization improvements are a separate upstream contribution and are not a runtime migration blocker.

## Completed physical preflight evidence

The following was run on the real Raspberry Pi and passed:

- [x] production SQLite online-copy shadow migration;
- [x] `SHADOW_PREFLIGHT=PASS`;
- [x] official `1.2.5.5` starts against the copied production DB;
- [x] SQLite `quick_check=ok`;
- [x] 83 tables before and after the official shadow start;
- [x] official container clean stop, exit code `0`;
- [x] old rollback compatibility check;
- [x] actual live `x2d.73` image starts against the official-migrated DB copy;
- [x] actual `x2d.73` rollback container clean stop, exit code `0`;
- [x] host -> X2D `8883` MQTT reachable;
- [x] host -> X2D `990` FTPS reachable;
- [x] host -> X2D `322` camera/RTSPS reachable;
- [x] host -> X2D `6000` camera/live-view reachable;
- [x] official image from `umbrel_main_network` can also reach all four X2D ports;
- [x] official image from `umbrel_main_network` can resolve/reach Spoolman.

The bridge-network connectivity result is useful diagnostic evidence only. It does **not** justify removing host mode because Virtual Printer requires the existing host-network arrangement.

## Shadow DB preflight

Script:

```bash
sudo bash scripts/bambuddy-shadow-preflight.sh
```

Default rollback image is the observed live `x2d.73` digest. `ROLLBACK_IMAGE` remains overrideable for future acceptance runs.

The shadow test intentionally uses an internal Docker network and copies of production data. It does not test Virtual Printer and never mounts the production DB into a test container.

Required result:

```text
SHADOW_PREFLIGHT=PASS
OFFICIAL_EXIT_CODE=0
ROLLBACK_EXIT_CODE=0
```

## Live RC helper

Script:

```bash
sudo bash scripts/bambuddy-live-rc.sh
```

The helper is designed for the currently observed Raspberry Pi baseline and performs:

1. verifies the running image is exactly `x2d.73` by immutable digest;
2. verifies host networking and Virtual Printer compose invariants;
3. verifies current Bambuddy health;
4. creates an online SQLite backup and compose/manifest/settings backup;
5. replaces only the Bambuddy image reference;
6. pulls the official immutable image;
7. restarts through `umbreld client apps.restart.mutate`;
8. requires the official image to become healthy;
9. requires host networking to remain enabled;
10. verifies app-proxy health;
11. verifies X2D ports `8883`, `990`, `322`, `6000` from the actual live container;
12. runs SQLite `quick_check` on production;
13. automatically restores the prior compose and pre-RC DB if a technical gate fails.

Successful technical result:

```text
LIVE_RC=PASS
NETWORK=host
Virtual Printer host-network compose was preserved; only the Bambuddy image changed.
```

The helper does **not** publish the Store or merge the PR.

## Remaining live acceptance

### Connectivity and UI

- [ ] Umbrel app opens through port `8280`;
- [ ] X2D reports `X2D / N6` and Online;
- [ ] live MQTT telemetry updates;
- [ ] FTPS-dependent functions work;
- [ ] camera opens and recovers after restart;
- [ ] temperatures/fans/chamber telemetry updates;
- [ ] AMS 2 Pro slots/trays are correct;
- [ ] maintenance/history load correctly.

### Virtual Printer — mandatory

- [ ] existing Virtual Printer configuration is still present;
- [ ] Virtual Printer starts successfully under official Bambuddy;
- [ ] Bambu Studio can see/use the Virtual Printer as expected;
- [ ] MQTT Virtual Printer endpoint works;
- [ ] FTP upload/control works;
- [ ] passive data transfer works;
- [ ] camera/proxy behavior used by the configured Virtual Printer still works;
- [ ] no new host ports conflict with other Umbrel services.

A failure here blocks publication even if normal printer monitoring works.

### Spoolman mode and persistence

Before tests, record the exact assigned Spoolman IDs.

- [ ] Bambuddy connects to the current Spoolman instance;
- [ ] spools are visible;
- [ ] every AMS slot maps to the intended Spoolman spool ID;
- [ ] internal Inventory is not the active assignment owner in Spoolman mode;
- [ ] restart Bambuddy and verify assignments are identical;
- [ ] restart Spoolman and verify reconnect + identical assignments;
- [ ] no stale FilaMan/internal assignment is resurrected.

### Single-material PETG accounting

- [ ] record PETG spool ID and remaining weight before print;
- [ ] print a small PETG object;
- [ ] job appears in Bambuddy history;
- [ ] exactly the intended PETG Spoolman spool decreases;
- [ ] no other spool decreases;
- [ ] debit is not duplicated after Bambuddy restart.

### PETG model + PLA support interface — highest priority

- [ ] record both Spoolman IDs/weights before print;
- [ ] PETG model usage is charged to PETG spool only;
- [ ] PLA support-interface usage is charged to PLA spool only;
- [ ] usage is not collapsed onto one spool;
- [ ] AMS/tray mapping follows the real material changes;
- [ ] restart does not alter or duplicate either debit.

### Bambu Studio initiated print

- [ ] start a small real print from Bambu Studio;
- [ ] Bambuddy discovers it;
- [ ] job reaches history;
- [ ] correct Spoolman spool is debited exactly once.

### Cancelled/failed print

- [ ] confirm `spoolman_report_partial_usage` setting;
- [ ] cancel a small print after measurable extrusion;
- [ ] usage behavior matches the configured setting;
- [ ] no duplicate debit after restart/recovery.

### AMS Filament Backup

Only perform with a safe small test.

- [ ] tray switch is observed;
- [ ] all usage is not incorrectly assigned to the original spool;
- [ ] ambiguous attribution blocks release rather than guessing positionally.

### External tray semantics

When exercised on the real X2D:

- [ ] active external global tray `254` is handled correctly;
- [ ] idle `tray_now=255` does not create a false debit;
- [ ] any model-specific second-external `255` mapping is validated from actual telemetry before debit.

## CI gates

The release candidate must keep these green:

- Store Node tests;
- shell syntax for shadow/live migration helpers;
- immutable official Bambuddy image pin;
- mandatory `network_mode: host`;
- mandatory `APP_HOST=192.168.0.100`;
- mandatory Virtual Printer advertise/PASV addresses;
- mandatory `NET_BIND_SERVICE`;
- Compose validation;
- anonymous official image pull;
- `linux/amd64` runtime startup + `/health`;
- `linux/arm64` runtime startup + `/health` under QEMU;
- PUID/PGID volume ownership validation;
- Spoolman startup smoke test.

## Release decision

Do not mark PR #9 ready, merge, or publish until the remaining real-device gates pass.

Minimum publication gate:

```text
CI
shadow migration
x2d.73 rollback compatibility
live official RC
Virtual Printer
X2D + AMS 2 Pro
Spoolman assignments/reconnect
single PETG accounting
PETG + PLA support accounting
Bambu Studio initiated accounting
cancelled-print accounting
```

## Rollback

Physical rollback target for this acceptance run:

```text
ghcr.io/mikefox303/bambuddy:1.2.5.5-x2d.73@sha256:9abf0d5bfb612dd1f473a7632f2b7aa404ef06db759e979b388bd7466cc84fb0
network_mode: host
APP_HOST: 192.168.0.100
```

The old fork repository/image must remain available until official runtime acceptance is complete.

## Fate of `MikeFox303/bambuddy`

After successful migration, keep the repository as:

- rollback/history reference;
- staging area for clean upstream PRs;
- archive of FilaMan-only work;
- source of localization contributions.

It should stop being the normal production runtime only after the real acceptance checklist is complete.
