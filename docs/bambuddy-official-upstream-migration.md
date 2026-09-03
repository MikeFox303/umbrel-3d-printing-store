# Bambuddy official upstream migration

Date: 2026-09-03

Status: **release candidate only — do not merge/publish until shadow + physical X2D/Spoolman gates pass**.

## Fixed reference points

### Selected upstream

- Latest stable checked at migration start: `maziggy/bambuddy v1.2.5.5`
- Stable tag commit: `c331a3aedf335e97e423add7463f715299fd89b0`
- Upstream `main` observed during audit: `2d16ed9ad01ec705d7e746d2ee48797ac20218c1`
- Fork `MikeFox303/bambuddy main` observed during audit: `f26ce2df334841cc8ead0c0933fdcb01bf33ba4c`
- Fork vs stable: 55 commits ahead, 0 behind at audit time.
- Fork vs current upstream main: diverged; merge base `1e2951899188ae0dff75ae221db03fd58274eda3`.

`v1.2.5.5` is intentionally selected instead of `daily`, `latest`, or upstream `main`. No known open issue found during the audit establishes a release-blocking X2D + Spoolman accounting regression in 1.2.5.5. Physical accounting tests below are still mandatory.

### Official image pin

```text
ghcr.io/maziggy/bambuddy:1.2.5.5@sha256:dc627d618cc3d3252ae4ab33af74c4679c66a9a06e0e3bbb7aefa32d1a4d4a07
```

Observed platform manifests:

```text
linux/amd64 sha256:d6a29fa4d379957d7dec39984ca495e97e367f9010ec482795fb491d8a33a381
linux/arm64 sha256:e6ebd1f258d3588490f03b9d60da865414d86b5d1ac21de866d6303ea2c3c271
```

The Umbrel package uses the multi-architecture manifest digest. It does not rebuild upstream under our GHCR namespace.

## Rollback snapshot before migration

These values describe production before any migration PR is merged:

```text
CURRENT_WORKING_VERSION=1.2.5.5-x2d.204
CURRENT_WORKING_IMAGE=ghcr.io/mikefox303/bambuddy:1.2.5.5-x2d.204
CURRENT_WORKING_DIGEST=sha256:0539eb76a64994081a868a30cb854097a0e9a9732dc0d60f05666748fe341743
CURRENT_WORKING_MAIN_SHA=115d417f200ba0a3bc699d27bb5a63b7b4434da9
```

The old image/digest must not be deleted while this migration is in acceptance.

## Network invariants

The current working Umbrel networking is the reference configuration. This migration MUST NOT add or require:

- `network_mode: host`
- Virtual Printer Proxy Mode
- MQTT/FTPS proxy changes
- changes to Umbrel routing
- X2D IP changes
- LAN Only / Developer Mode changes
- Tailscale/host-socket mounts for Virtual Printer

The RC keeps the existing `app_proxy -> server:8000`, `PUID=1000`, `PGID=1000`, `/app/data`, and `/app/logs` packaging unchanged.

## Downstream audit classification

### A. Already upstream — delete from production fork dependency

- Upstream stable core through `v1.2.5.5` is now consumed directly from the official image.
- Fork commits that merely sync/copy upstream commits are not downstream requirements.
- Upstream already owns the Spoolman inventory implementation, `spoolman_slot_assignments`, AMS slot APIs, tag/fingerprint handling, print usage tracking, failed/cancelled-print controls, archive handling for jobs Bambuddy did not dispatch, dual-nozzle/X2D support, FTPS, camera, and model recognition.
- Upstream-main-only CI/dependency commits after stable are not reasons to use `main`; they wait for the next stable.

### B. FilaMan-only — remove from runtime

Do not reapply these to official Bambuddy:

- `backend/app/api/routes/filaman_usage.py`
- durable FilaMan WebSocket/usage replay ledger
- FilaMan inventory-only assignment policy
- FilaMan reconciliation logic
- FilaMan-specific API endpoints
- FilaMan-oriented aggregate usage fallback
- fork wiring whose purpose is to install the above at startup

The fork's `fork_safety.py` explicitly describes itself as compatibility protection where the downstream FilaMan/X2D inventory extension interacts with upstream Spoolman mode. That is not evidence that clean upstream Spoolman requires the patch.

### C. Umbrel / release infrastructure — keep outside Bambuddy core

Keep the useful engineering, but in `umbrel-3d-printing-store`:

- immutable digest pinning
- anonymous GHCR pull validation
- amd64/arm64 runtime smoke tests
- Compose/manifest validation
- shadow DB preflight
- rollback snapshot and compatibility test
- release-candidate PR workflow
- stale-workflow protection
- health checks

The former workflow that automatically published `MikeFox303/bambuddy` X2D builds is replaced by a read-only upstream-stable checker. It cannot push to `main`.

### D. Generic X2D bugfix absent upstream — no proven blocker yet

No fork-only X2D core patch has been proven necessary for **clean official 1.2.5.5 + Spoolman** during repository audit.

The downstream aggregate fallback and inventory policies were developed around the FilaMan/inventory-only extension. They are therefore rejected by default for the new runtime. If a physical gate below fails, reproduce it on official upstream first and isolate the smallest generic X2D fix with an upstream-compatible test before carrying any patch.

### E. Generic Spoolman bugfix absent upstream — candidate only, not carried

The fork contains guards intended to prevent stale internal-inventory assignments from affecting Spoolman mode. Those guards are coupled to the downstream inventory-only/FilaMan extension, while official upstream already maintains a dedicated `spoolman_slot_assignments` model/API.

Decision: **do not carry the guard into the RC**. The mandatory restart, Bambu Studio, single-material, multi-material and cancelled-print tests are the proof gate. If official upstream fails one of those tests, open an upstream-compatible bug/test rather than silently restoring the fork.

### F. RU/UK localization — upstream PR candidate, non-blocking

Do not ship large fork locale files in the runtime. Preserve quality corrections as a separate upstream contribution, including at least:

Russian:

```text
Не активно -> Неактивно
многостольный -> многопластинный
```

Ukrainian:

```text
за умовчанням -> за замовчуванням
Тестове підключення -> Перевірити підключення
Продавець -> Виробник
```

Translation merge is not a runtime migration gate.

## Container compatibility contract

The official `v1.2.5.5` Dockerfile matches the existing Umbrel package contract:

- configurable `PORT`, default `8000`
- `PUID` / `PGID` handled by the official entrypoint
- `DATA_DIR=/app/data`
- `LOG_DIR=/app/logs`
- `/health` Docker health endpoint
- image exposes required Bambuddy service ports internally but the Umbrel package only proxies port 8000

No production networking changes are required by the image.

## Shadow DB preflight

Run before installing the RC:

```bash
cd /path/to/umbrel-3d-printing-store
sudo bash scripts/bambuddy-shadow-preflight.sh
```

The script:

1. opens the production SQLite DB read-only;
2. creates an online SQLite backup into `/tmp/bambuddy-official-shadow`;
3. never mounts production `/data` into a test container;
4. starts the official image on a separate container/name/host port;
5. uses a temporary **internal** Docker bridge, not `host` and not `umbrel_main_network`, so shadow startup cannot contact X2D or Spoolman;
6. validates `/health`, clean shutdown and SQLite `quick_check`;
7. starts the current production image against a second copy of the migrated shadow DB;
8. blocks release if rollback-image compatibility fails.

Required result:

```text
SHADOW_PREFLIGHT=PASS
OFFICIAL_EXIT_CODE=0
ROLLBACK_EXIT_CODE=0
```

Keep `official-container.log`, `rollback-container.log`, `bambuddy-before-upstream.db`, and the migrated shadow DB as migration evidence. Do not publish if startup migration fails or rollback compatibility fails.

## Physical X2D + Spoolman acceptance checklist

These tests cannot be truthfully replaced by CI because they require the real X2D, AMS 2 Pro, current Spoolman DB, real tray telemetry and real print completion events.

### 1. Connectivity / UI

- [ ] Umbrel app opens through port 8280 / app proxy.
- [ ] X2D reports model `X2D / N6` and Online.
- [ ] MQTT status is live.
- [ ] FTPS operations required by normal Bambuddy use work.
- [ ] RTSPS camera opens and recovers after restart.
- [ ] Temperatures, fans and chamber data update.
- [ ] AMS 2 Pro slots/trays are correct.
- [ ] Maintenance and print history load.
- [ ] No Virtual Printer / Proxy Mode is enabled as part of this migration.

### 2. Spoolman mode and persistence

Record all assigned Spoolman IDs before testing.

- [ ] Bambuddy connects to the current Spoolman instance.
- [ ] Spools are visible.
- [ ] Every AMS slot points to the intended Spoolman spool ID.
- [ ] Internal Inventory does not appear as an active assignment source while Spoolman mode is active.
- [ ] Restart Bambuddy; assignments remain identical.
- [ ] Restart Spoolman; Bambuddy reconnects and assignments remain identical.
- [ ] No stale assignment is resurrected from the former internal/FilaMan mode.

### 3. Single-material accounting — PETG

Before print record:

```text
Spoolman spool ID:
remaining weight:
AMS unit/tray:
material:
color:
```

Print a small one-colour PETG object.

After completion:

- [ ] Bambuddy print history contains the job.
- [ ] Bambuddy usage is non-zero and plausible.
- [ ] exactly the intended PETG Spoolman spool decreased;
- [ ] no other spool decreased;
- [ ] the job was not charged twice;
- [ ] a Bambuddy restart does not create a second debit.

### 4. Mandatory multi-material accounting — PETG model + PLA support interface

Use two different physical/Spoolman spools in AMS 2 Pro and record both IDs/weights before print.

- [ ] PETG model usage is charged only to the PETG spool.
- [ ] PLA support-interface usage is charged only to the PLA spool.
- [ ] total usage is not collapsed onto one spool.
- [ ] no positional AMS mapping error occurs.
- [ ] tray-change history matches actual material changes.
- [ ] after completion and restart, both Spoolman weights remain consistent.

This is the highest-priority release gate.

### 5. Bambu Studio initiated print / no local 3MF assumption

Start a small print from Bambu Studio rather than Bambuddy.

- [ ] Bambuddy discovers the running job.
- [ ] the job enters history.
- [ ] the active spool is resolved from reliable printer/tray/job telemetry rather than guessed positionally when better data exists.
- [ ] the correct Spoolman spool is debited once.

### 6. Failed / cancelled print

Set/check Bambuddy's `Report partial usage for failed/cancelled prints` setting before the test, then start a small print and cancel after measurable extrusion.

- [ ] behavior matches that setting.
- [ ] if enabled, only the partial usage is reported.
- [ ] if disabled, no unexpected partial debit is made.
- [ ] restart/recovery does not duplicate the debit.

### 7. AMS Filament Backup

Only perform when a safe small test can intentionally trigger backup-spool switching.

- [ ] Bambuddy observes the tray switch.
- [ ] it does not debit all usage from the original spool.
- [ ] if upstream cannot attribute usage safely, release is blocked; do not add a positional guess.

### 8. External spool IDs

When external tray behavior is exercised:

- [ ] global tray `254` is handled as an external spool when genuinely active.
- [ ] idle `255` is never interpreted as a real active spool.
- [ ] second external path / model-specific `255` semantics are validated from real X2D telemetry before any debit is allowed.

## CI gates

Before merge all automatic checks must pass:

- Node release-helper tests
- Compose validation
- official Bambuddy immutable image regex
- explicit prohibition of `network_mode: host` in Bambuddy package
- anonymous official GHCR pull
- `linux/amd64` runtime start + `/health`
- `linux/arm64` runtime start + `/health` under QEMU
- PUID/PGID volume ownership check
- Spoolman startup smoke test

The scheduled Bambuddy updater is read-only. A newer upstream stable produces a warning only; it is never auto-published. Every future stable must get a new acceptance PR and immutable digest.

## Release decision

Merge/publish only after all of these are recorded as PASS:

```text
CI
shadow migration
rollback compatibility
X2D connectivity
AMS 2 Pro
camera
Spoolman reconnect/persistence
single PETG accounting
PETG + PLA support accounting
Bambu Studio initiated accounting
cancelled-print accounting
```

Until then `main` remains the current `1.2.5.5-x2d.204` production package.

## Rollback after eventual publication

If official stable proves bad after release:

1. stop/recreate only the Bambuddy Community App using the recorded old compose/image digest;
2. restart Bambuddy;
3. if the preflight proved the migrated DB backward compatible, retain the DB;
4. if a future upstream release introduces a non-backward-compatible migration, restore the pre-upgrade DB snapshot together with the old image.

No networking rollback should be necessary because this migration does not change networking.

## Fate of `MikeFox303/bambuddy`

Do not delete the repository. After production migration classify/retain it as:

- historical rollback reference;
- staging area for clean upstream PRs;
- archive of FilaMan-only work;
- source of localization improvements.

It must no longer be the normal production runtime once this migration is accepted.
