# FoxForge for UmbrelOS

This package installs FoxForge behind the Umbrel App Proxy and persists application state under the Umbrel app data directory.

The current Store package is **Pre-Alpha 5 physical-validation Candidate 7**, not the final `v0.1.0-alpha.5` release.

## Immutable Candidate 7 identity

- FoxForge source: `4f769ca89d466d2cbe41360848b6343ec5a8eb36`
- image tag: `ghcr.io/mikefox303/foxforge:sha-4f769ca`
- immutable multi-architecture digest: `sha256:0000e7a6c74056a0fff2e019c31a8cffc6d7fb2d3ec1fefdf587354a4d64c9b7`
- platforms: `linux/amd64`, `linux/arm64`
- Umbrel package: `0.1.0-alpha.4.3-umbrel.7`
- semantic target: `v0.1.0-alpha.5` — still unpublished

The `0.1.0-alpha.4.3` base remains tied to the latest published FoxForge semantic release for upstream-version auditing. The `-umbrel.7` suffix identifies the seventh installable Pre-Alpha 5 validation package.

Candidate 6 is historical and **failed the real X2D Add Printer physical gate**. It must not be used as Candidate 7 evidence. Candidate 1–6 physical evidence must not be relabeled or carried across this source/image/package identity.

Automated package/runtime checks do not replace representative physical validation on Raspberry Pi 5/UmbrelOS, Bambu X2D + AMS 2 Pro, or Moonraker/OpenKE.

## Why Candidate 7 exists

Candidate 6 reached the real X2D setup test, where the exact payload could pass UI Verify and then fail during Add Printer with a normalized internal adapter error. FoxForge traced that to connection-lifecycle behavior that could create rapid overlapping/reused Bambu MQTT sessions.

Candidate 7 includes the replacement fix from FoxForge PR #184:

- the staged **Provider → Connection → Identity → Verify** flow remains;
- UI Verify remains non-persistent and must match the exact payload being saved;
- Add Printer no longer opens a disposable backend connection immediately before the real live connection;
- the adapter that will join the live fleet performs the single backend-authoritative Add connection before durable config/secrets are accepted;
- a failed Add connection removes the transient fleet entry and persists no dead printer;
- Bambu MQTT uses a short **per-session client ID**, so Verify/Add/reconnect/parallel-process sessions do not deliberately reuse one serial-derived broker identity;
- public setup errors remain normalized/secret-safe while unexpected adapter exceptions are logged server-side;
- Update Printer keeps its separate preflight and rollback path to protect a known-good existing configuration.

Candidate 7 otherwise retains the Candidate 6 capability milestone: capability-driven printer UI, typed Material Topology, thermal telemetry, queue/job control, guarded Bambu routing, staged `.3mf` inspection and provider-scoped accounting validation.

## Bambu routing and UI contract

Candidate 7 includes:

- capability-driven application shell and Printer Detail views;
- typed Material Topology with explicit `fixed`, `dynamic`, `unknown` and stale route states;
- Bambu thermal telemetry through typed common capabilities rather than model-name switches;
- immutable staged `.3mf` inspection and plate-scoped material requirements;
- explicit operator material-source binding before routed Bambu dispatch;
- fresh source/topology revalidation immediately before submit;
- fail-closed handling of malformed or ambiguous selected-plate toolhead metadata, including `TOOLHEAD_METADATA_INVALID`;
- `project_file.nozzle_mapping` only from a complete compiler-owned route;
- Bambu external sources 254/255 stay `-1` in flat `ams_mapping`, retain real IDs in `ams_mapping2`, and receive a nozzle only from compiler-owned toolhead routing;
- queue/inventory/accounting UI with exact decimal mass handling and explicit reconciliation;
- guarded Pause/Resume/Cancel against the observed vendor job identity.

FoxForge never auto-picks a spool by color/material and never guesses a left/right nozzle when routing evidence is ambiguous.

## Candidate 7 filament-accounting validation mode

The generic FoxForge runtime default remains `FOXFORGE_FILAMENT_ACCOUNTING_MODE=disabled`. This Umbrel validation package deliberately sets:

```text
FOXFORGE_FILAMENT_ACCOUNTING_MODE=bambu-validation
```

The safety boundary is provider-scoped:

- automatic pre-dispatch accounting enforcement applies only to printers whose adapter kind is `bambu`;
- Moonraker/Klipper and unknown/future providers remain outside this automatic enforcement mode;
- planning uses explicit FoxForge spool assignments and exact decimal gram estimates;
- accounting does not choose the physical source or toolhead;
- FoxForge does not infer consumed grams from print progress or vendor telemetry;
- confirmed completion settles the reserved estimate exactly once;
- attempted/started failed or cancelled jobs require explicit actual-mass reconciliation;
- `INDETERMINATE` outcomes keep reservations held until the operator reconciles the real outcome;
- assignment drift or insufficient capacity blocks dispatch instead of silently moving the reservation.

Candidate 7 physical validation must prove routed Bambu dispatch and weighed-spool accounting evidence before this behavior can be accepted for final Alpha 5.

## Write access on Umbrel

FoxForge keeps application authorization separate from Umbrel App Proxy authentication. The package maps Umbrel's deterministic per-app password to the FoxForge operator credential:

```text
APP_PASSWORD → FOXFORGE_COMMAND_TOKEN
```

To use protected actions such as Add Printer, inventory mutations, queue/accounting actions or Pause/Resume/Cancel:

1. open FoxForge through Umbrel;
2. choose **Unlock writes**;
3. enter the app password shown by Umbrel;
4. FoxForge keeps the credential only in JavaScript memory for the current tab;
5. after reload/tab restart, unlock again.

Umbrel App Proxy is defense in depth, not the FoxForge application principal. The package does **not** use host networking, privileged mode, or the Docker socket.

## First start and persistence

On first start FoxForge creates and maintains:

- `data/config.json` — persistent non-secret printer configuration;
- `data/secrets.json` — application-owned secret store for Bambu access codes and Moonraker API keys;
- `data/foxforge.sqlite3` — durable queue, inventory, accounting, idempotency and audit state;
- `data/artifacts/` — content-addressed staged `.gcode` / `.3mf` payloads.

Do not manually place credentials in `config.json`. The entire `/data` directory may contain credential-bearing/recovery material and must be treated as sensitive.

## Bambu Lab LAN setup

Use **Add Printer → Bambu Lab (LAN mode)**. The wizard is **Provider → Connection → Identity → Verify**. FoxForge can scan a bounded server-visible private subnet or accept the printer manually.

Enter the display name, model, serial number, host/IP and LAN access code. Before Save, the exact payload must pass Verify. If host, access code, model, identity or another verified field changes, Save disables until a new Verify succeeds.

For Add Printer, the live adapter connection is the backend-authoritative preflight. Durable config/secrets are written only after that connection succeeds and a valid initial printer state is obtained. A failed Add is not persisted. Update Printer separately verifies replacement connectivity before replacing a known-good configuration and rolls back if the replacement cannot be installed safely.

The non-secret persisted shape is equivalent to:

```json
{
  "schemaVersion": 2,
  "printers": [
    {
      "printerId": "bambu-<stable-id>",
      "displayName": "Bambu Lab X2D",
      "vendor": "Bambu Lab",
      "model": "X2D",
      "serialNumber": "YOUR_PRINTER_SERIAL",
      "adapterKind": "bambu",
      "settings": {
        "host": "192.168.1.100"
      }
    }
  ]
}
```

The LAN access code is stored separately in `data/secrets.json`. FoxForge uses Bambu LAN MQTT on port `8883` and implicit FTPS on port `990` by default.

## Moonraker / Klipper setup

Use **Add Printer → Klipper / Moonraker** and provide a stable local printer ID, display name and Moonraker URL. API keys, when needed, go through the SecretStore boundary.

Example non-secret configuration:

```json
{
  "schemaVersion": 2,
  "printers": [
    {
      "printerId": "ender3-v3-ke",
      "displayName": "Ender-3 V3 KE",
      "vendor": "Creality",
      "model": "Ender-3 V3 KE",
      "adapterKind": "moonraker",
      "settings": {
        "base_url": "http://192.168.1.120:7125"
      }
    }
  ]
}
```

Moonraker/Klipper automatic filament-accounting enforcement is not enabled by the Candidate 7 `bambu-validation` mode.

## Mixed fleet and diagnostics

Bambu and Moonraker printers can coexist in one FoxForge instance. A powered-off or temporarily unreachable printer does not prevent startup. Per-printer reconnect supervision retries independently with bounded backoff/jitter.

For a configured printer, open **Diagnostics** to inspect normalized reconnect history without exposing raw credentials/vendor exceptions. Add Printer failures remain inline setup outcomes until the printer exists.

## Safe print workflow

For supported print files:

1. select a local `.gcode` or `.3mf`;
2. FoxForge hashes and stages the content under `data/artifacts/`;
3. for a routed Bambu `.3mf`, inspect the selected plate and logical material requirements;
4. bind each required material to an explicit currently loaded physical source;
5. FoxForge validates slicer toolhead metadata and compiles source→toolhead routing;
6. create the explicit filament plan/reservation required by Candidate 7 Bambu accounting;
7. enqueue the artifact;
8. press **Start** separately;
9. immediately before submit, FoxForge revalidates current material source, topology, assignment and accounting readiness;
10. only a complete proven route can emit `ams_mapping` / `ams_mapping2` / `nozzle_mapping`;
11. if the remote side effect becomes `INDETERMINATE`, reconcile whether the print started instead of blindly retrying.

## Pre-Alpha 5 Candidate 7 physical validation sequence

Candidate 7 must not be promoted to final Alpha 5 from CI alone. On the real Raspberry Pi 5/Umbrel + X2D + AMS 2 Pro deployment:

1. install/update the exact digest-pinned package and confirm `0.1.0-alpha.4.3-umbrel.7`, source `4f769ca89d466d2cbe41360848b6343ec5a8eb36`, and digest `sha256:0000e7a6c74056a0fff2e019c31a8cffc6d7fb2d3ec1fefdf587354a4d64c9b7`;
2. unlock writes using the app password shown by Umbrel and confirm reload clears browser write access;
3. add the X2D through the staged GUI wizard; after successful Verify, change one field and confirm Save disables until re-verification;
4. specifically confirm the Candidate 6 blocker is gone: **Verify → Add** must persist and connect the X2D without an internal adapter error;
5. confirm live X2D state and Bambu thermal telemetry;
6. confirm AMS 2 Pro A1–A4 loaded with PETG, External Left empty, External Right loaded with PLA, and explicit typed Material Topology routes/toolheads;
7. submit an intentionally invalid Update and confirm the known-good saved printer survives;
8. restart FoxForge and confirm automatic reconnect;
9. temporarily make the X2D unreachable, observe sanitized diagnostics, restore reachability and confirm recovery;
10. record the measured starting mass of the spool selected for accounting validation;
11. stage a known-safe `.3mf`, select the plate, bind materials to physical sources and create the explicit accounting plan/reservation;
12. confirm corrupt or ambiguous selected-plate toolhead metadata remains blocked;
13. only after the no-print checks pass, press Start and verify FTPS upload + MQTT `project_file` acknowledgement;
14. record sanitized effective `ams_mapping`, `ams_mapping2` and `nozzle_mapping` evidence;
15. verify exactly one intended physical job starts and FoxForge observes the same job;
16. after completion, weigh/measure the same spool and compare measured usage with reservation/settlement evidence;
17. separately verify explicit reconciliation is required for a safe attempted/started non-completed scenario rather than guessing actual usage;
18. record failures as well as successes before changing FoxForge milestone status.

The exact source, OCI digest, package version and eventual Store merge commit must stay attached to the validation evidence. Any application/image/package-definition change after evidence begins invalidates the affected evidence and requires another immutable candidate.

## Current limitations

- this validation candidate is **not** final `v0.1.0-alpha.5`;
- Bambu Virtual Printer is not included;
- Bambu automatic filament accounting is enabled only as a physical-validation mode and is not yet accepted as production behavior;
- Moonraker/Klipper automatic filament accounting remains disabled pending its own evidence gate;
- persistent farm scheduling/distributed leases are not implemented yet;
- deep AMS/CFS operations such as drying, HMS actions, K profiles and broader FTS controls remain future typed capabilities;
- physical Bambu X2D validation is still required for connection lifecycle, transport/certificates, material routing, project delivery, job control and accounting;
- physical Moonraker/OpenKE validation remains a separate track.

The interface supports English, Russian and Ukrainian.

## Backup and upgrade

Back up the complete FoxForge `data/` directory before upgrading early-alpha builds. It contains durable application state and sensitive recovery/credential material.
