# FoxForge for UmbrelOS

This package installs FoxForge behind the Umbrel App Proxy and persists all application state under the app data directory.

The current Store package is **Pre-Alpha 5 physical-validation Candidate 6**, not the final `v0.1.0-alpha.5` release.

Candidate 6 exact application identity:

- FoxForge source: `78ace6f7b7412aa0d3fc58bed095aecdf9920f94`;
- image tag: `ghcr.io/mikefox303/foxforge:sha-78ace6f`;
- immutable multi-architecture digest: `sha256:b01f1d44199a4413167ee2369c0dfbcafa602312442772d27de18e04c24ed0eb`;
- platforms: `linux/amd64`, `linux/arm64`;
- Umbrel package: `0.1.0-alpha.4.3-umbrel.6`;
- semantic target: `v0.1.0-alpha.5` — still unpublished.

The `0.1.0-alpha.4.3` base remains tied to the latest published FoxForge semantic release for upstream-version auditing. The `-umbrel.6` suffix identifies the sixth installable Pre-Alpha 5 validation package. Candidate 5 is historical and must not be used as Candidate 6 evidence; Candidate 1–5 physical evidence must not be relabeled or carried across this new source/image identity.

This remains early-alpha software. Automated package/runtime checks do not replace representative physical validation on Raspberry Pi 5/UmbrelOS, Bambu X2D + AMS 2 Pro, or Moonraker/OpenKE.

## What Candidate 6 adds

Compared with Candidate 5, Candidate 6 carries the full C6 software milestone and its exact software gate:

- staged **Provider → Connection → Identity → Verify** Add Printer flow;
- Bambu connection preflight before persistence and rollback-safe Update Printer behavior;
- stable Bambu printer identity derived from normalized serial number;
- normalized, secret-safe setup/reconnect diagnostics;
- capability-driven application shell, printer cards, Control and Materials views;
- typed Material Topology with explicit `fixed`, `dynamic`, `unknown` and stale route states;
- Bambu thermal telemetry surfaced through typed capabilities rather than model-name switches;
- immutable staged `.3mf` inspection and plate-scoped material requirements;
- explicit operator material-source binding before routed Bambu dispatch;
- compiler-owned toolhead routing with fresh source/topology revalidation immediately before submit;
- fail-closed handling of malformed or ambiguous selected-plate toolhead metadata, including `TOOLHEAD_METADATA_INVALID`;
- `project_file.nozzle_mapping` only from a complete proven route;
- Bambu external sources 254/255 remain `-1` in flat `ams_mapping`, retain their real IDs in `ams_mapping2`, and receive a nozzle only from the compiled route;
- queue/inventory/accounting operator UI with exact decimal mass handling and explicit reconciliation controls;
- guarded Pause/Resume/Cancel using the observed vendor job identity;
- EN/RU/UK localization and responsive acceptance across phone, tablet, desktop and ultrawide targets.

FoxForge never auto-picks a spool by color/material and never guesses a left/right nozzle when routing evidence is ambiguous.

## Candidate 6 filament-accounting validation mode

The generic FoxForge runtime default remains `FOXFORGE_FILAMENT_ACCOUNTING_MODE=disabled`. This Umbrel Candidate 6 package deliberately sets:

```text
FOXFORGE_FILAMENT_ACCOUNTING_MODE=bambu-validation
```

This is a provider-scoped physical-validation gate, not blanket multi-vendor enablement:

- automatic pre-dispatch accounting enforcement applies only to printers whose adapter kind is `bambu`;
- Moonraker/Klipper and unknown/future providers remain outside this automatic enforcement mode;
- planning uses exact decimal gram estimates and explicit FoxForge spool assignments;
- accounting does not choose the physical source or toolhead — the material-routing compiler remains authoritative;
- FoxForge does not infer consumed grams from print progress or vendor telemetry;
- confirmed completion settles the reserved estimate exactly once;
- attempted/started failed or cancelled jobs require explicit actual-mass reconciliation;
- `INDETERMINATE` outcomes keep reservations held until the operator reconciles the real outcome;
- assignment drift or insufficient capacity blocks rather than silently changing the reserved spool.

Candidate 6 physical validation must therefore verify both routed Bambu dispatch and weighed-spool accounting evidence before this mode can be considered accepted for Alpha 5.

## Write access on Umbrel

FoxForge keeps application authorization separate from Umbrel App Proxy authentication. The package keeps application write authentication enabled and maps Umbrel's deterministic per-app password to the FoxForge operator credential:

```text
APP_PASSWORD → FOXFORGE_COMMAND_TOKEN
```

To use protected actions such as **Add Printer**, inventory mutations, accounting actions, queue mutations or Pause/Resume/Cancel:

1. open FoxForge through Umbrel;
2. choose **Unlock writes** in FoxForge;
3. enter the FoxForge app password shown by Umbrel;
4. FoxForge keeps that credential only in JavaScript memory for the current tab and sends it only for protected commands;
5. re-enter it after a page reload/tab restart, or after explicitly locking writes.

Umbrel App Proxy remains defense in depth; it is not treated as the FoxForge application principal. Direct backend access without the correct operator credential fails closed for protected commands.

The package does **not** use host networking, privileged mode, or the Docker socket.

## First start

Install **FoxForge** from this Community App Store and open it once. The server creates and maintains:

- `data/config.json` — persistent non-secret printer connection configuration;
- `data/secrets.json` — application-owned secret store for Bambu LAN access codes and Moonraker API keys;
- `data/foxforge.sqlite3` — durable queue, inventory, accounting, command-idempotency and audit state;
- `data/artifacts/` — content-addressed staged `.gcode` / `.3mf` payloads.

Use **Add Printer** in the FoxForge web UI to configure supported printers. Do not manually place credentials in `config.json`; current FoxForge persists Bambu access codes and Moonraker API keys through its SecretStore boundary. Legacy inline credentials are migrated into `secrets.json` on startup. The complete `/data` directory is credential-bearing data and must be treated as sensitive.

## Bambu Lab LAN setup

Use **Add Printer → Bambu Lab (LAN mode)**. The staged wizard is **Provider → Connection → Identity → Verify**. You can scan a bounded server-visible private subnet or enter the printer manually. FoxForge asks for:

- display name;
- Bambu model;
- printer serial number;
- printer IP/hostname;
- LAN access code.

FoxForge normalizes the serial number and creates the stable local printer ID automatically. Before saving, the current exact payload must pass Verify. If host, access code, identity, model or another payload field changes after verification, Save is disabled again until a new Verify succeeds. The backend independently repeats connection preflight before durable persistence. A failed validation is not persisted. Editing an existing printer follows the same test-before-save rule: a failed validation leaves the previous working configuration intact.

The resulting non-secret `config.json` entry is equivalent to:

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

The LAN access code is stored separately in `data/secrets.json` and is not returned by public read models.

FoxForge uses Bambu LAN MQTT on port `8883` and implicit FTPS on port `990` by default. Optional advanced settings include `mqtt_port`, `ftps_port`, `username`, `connect_timeout_seconds`, `command_timeout_seconds`, `tls_verify`, and independent MQTT/FTPS certificate SHA-256 pins.

## Moonraker / Klipper setup

Use **Add Printer → Klipper / Moonraker** and provide a stable local printer ID, display name and Moonraker URL. If the Moonraker server requires an API key, enter it in the UI; FoxForge stores it through the same SecretStore boundary.

The non-secret persisted shape is equivalent to:

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

Current FoxForge applies explicit destination/redirect/address-resolution policy to Moonraker endpoints. Candidate 6 does not enable automatic Moonraker filament-accounting enforcement.

## Mixed fleet

Bambu and Moonraker printers can coexist in the same FoxForge instance. `printerId` values must remain unique and stable.

A printer that is powered off or temporarily unreachable does not prevent FoxForge from starting. Per-printer reconnect supervision retries independently with bounded backoff/jitter. Open the printer's **Diagnostics** tab to inspect normalized reconnect history without exposing raw vendor errors.

## Safe print workflow

For supported print files the browser workflow is intentionally staged:

1. select a local `.gcode` or `.3mf` file;
2. FoxForge calculates SHA-256 in the browser and uploads file bytes only;
3. the backend verifies and stores the content-addressed artifact under `/data/artifacts`;
4. for a routed Bambu `.3mf`, FoxForge inspects the immutable staged artifact, exposes selected-plate material requirements and requires explicit physical source bindings;
5. FoxForge validates slicer toolhead metadata and fails closed if required project metadata is malformed, ambiguous, encrypted, oversized or otherwise invalid;
6. FoxForge compiles each binding against current material-system/topology snapshots and persists the proven toolhead route;
7. Candidate 6 accounting requires an explicit filament plan/reservation for the Bambu queue entry before dispatch;
8. enqueue the artifact for the selected printer;
9. press **Start** separately to dispatch the print;
10. immediately before Bambu submit, FoxForge revalidates source presence, topology freshness, compiled source→toolhead routing and provider-scoped accounting readiness;
11. only a complete proven route can produce Bambu `ams_mapping` / `ams_mapping2` / `nozzle_mapping` fields;
12. if the remote side effect becomes `INDETERMINATE`, reconcile whether the print started instead of retrying blindly.

The client filesystem path is never sent as a server-side path, receipt-bearing jobs are never blindly redispatched, and routing ambiguity is a blocker rather than an invitation to choose a source or nozzle heuristically.

## Pre-Alpha 5 Candidate 6 physical validation sequence

Candidate 6 must not be promoted to final Alpha 5 based only on Store CI. On the real Raspberry Pi 5/Umbrel + X2D + AMS 2 Pro deployment, validate at minimum:

1. install/update this exact digest-pinned package and confirm package `0.1.0-alpha.4.3-umbrel.6`, source `78ace6f7b7412aa0d3fc58bed095aecdf9920f94`, and image digest `sha256:b01f1d44199a4413167ee2369c0dfbcafa602312442772d27de18e04c24ed0eb`;
2. unlock writes from the GUI using the FoxForge app password shown by Umbrel and confirm a browser reload does not retain it;
3. add the X2D through the staged GUI wizard with its real serial, host and LAN access code; after successful Verify, change one field and confirm Save disables until re-verification;
4. confirm live X2D connection, job state and Bambu thermal telemetry;
5. confirm the real material fixture is represented without guessing: AMS 2 Pro A1–A4 loaded with PETG, External Left empty, External Right loaded with PLA, and both external routes/toolheads shown explicitly by typed Material Topology;
6. edit one connection field to an intentionally invalid value and confirm Update fails without replacing the working saved printer, then restore the valid form values;
7. retry a failed Add/Update submission without changing its browser command identity when practical and confirm FoxForge replays the same sanitized terminal outcome instead of executing the mutation twice;
8. restart FoxForge and confirm the saved printer reconnects without being re-added;
9. temporarily make the X2D unreachable, confirm a sanitized reconnect incident appears, then restore reachability and confirm recovery;
10. create/assign the test spool records needed for the selected Bambu material sources and record their measured starting mass;
11. stage a known-safe `.3mf`, inspect its selected plate/material requirements, explicitly bind each requirement to a currently loaded physical source, review the compiler-owned toolhead/nozzle path, and create the explicit accounting plan;
12. confirm corrupt or ambiguous selected-plate toolhead metadata remains blocked and is never rescued by a fixed source route;
13. only after the no-print checks above pass, press **Start** separately and verify FTPS upload + MQTT `project_file` acknowledgement on the physical X2D, recording sanitized `ams_mapping`, `ams_mapping2` and `nozzle_mapping` evidence;
14. verify the physical X2D starts exactly one intended job and FoxForge observes the same vendor job/progress;
15. during the test print, verify guarded Pause, Resume and Cancel behavior only against the same observed vendor job identity when the chosen test procedure requires those controls;
16. after a completed accounting test, weigh/measure the relevant spool and compare the real change with the FoxForge reservation/settlement evidence; do not infer actual use from printer progress;
17. separately exercise a safe reconciliation scenario for a started/attempted non-completed outcome and confirm explicit reconciliation is required rather than an automatic guessed debit;
18. record failures as well as successes before changing any physical-validation status in the FoxForge repository.

The exact source commit, immutable image digest and eventual Store merge commit must be recorded with the validation evidence. Any application/image/package-definition change after this candidate invalidates affected physical evidence and requires another immutable candidate.

## Current limitations

- this validation candidate is **not** the final `v0.1.0-alpha.5` release;
- Bambu Virtual Printer is not included;
- Bambu automatic filament accounting is enabled only as the Candidate 6 physical-validation mode and is not yet accepted as production behavior;
- Moonraker/Klipper automatic filament accounting remains disabled pending its own evidence gate;
- persistent farm scheduling/distributed leases are not implemented yet;
- deep Bambu AMS/CFS operations such as drying, HMS actions, K profiles and broader FTS controls remain future typed capabilities;
- physical Bambu X2D validation is still required for transport, certificate, material routing, project delivery, job control, accounting and lifecycle behavior;
- physical Moonraker/OpenKE validation remains required for endpoint-policy compatibility, upload/start/job-control/lifecycle behavior;
- representative Raspberry Pi 5/UmbrelOS install, restart/persistence, real proxy/write path, printer-network reachability and SSE reconnect/resync validation remain required.

The interface supports English, Russian and Ukrainian.

## Backup and upgrade

Back up the complete FoxForge app `data/` directory before upgrading early alpha versions. Current `/data` contains configuration, SQLite queue/inventory/accounting state, staged artifacts and credential-bearing/recovery material, so backups must be treated as sensitive.
