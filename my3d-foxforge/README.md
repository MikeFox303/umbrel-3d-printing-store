# FoxForge for UmbrelOS

This package installs FoxForge behind the Umbrel App Proxy and persists all application state under the app data directory.

The current Store package is a **Pre-Alpha 5 physical-validation candidate**, not the final `v0.1.0-alpha.5` release. Candidate 4 is built from FoxForge source commit `c11f7145b4354aa79c8f0fad223648240e652bac` and is intended to validate the real Raspberry Pi 5 + Umbrel + Bambu X2D + AMS 2 Pro path before the semantic Alpha 5 release is created.

The Store version uses the package-local identity `0.1.0-alpha.4.3-umbrel.4`. The `0.1.0-alpha.4.3` base remains tied to the latest published FoxForge release for upstream-version auditing, while `-umbrel.4` identifies the fourth installable physical-validation package. The exact newer FoxForge source commit and immutable image digest are recorded separately in the package contract and release notes. This package is a validation candidate only and must not be treated as the final Alpha 5 release.

This remains early-alpha software. Automated package/runtime checks do not replace representative physical validation on Bambu X2D, Moonraker/OpenKE or Raspberry Pi 5/UmbrelOS.

## What this validation candidate adds

Compared with the current Alpha 4.3 release package, candidate 4 includes the Pre-Alpha 5 Bambu connection and print-routing work already merged into FoxForge `main`:

- Add Printer validates a Bambu connection before persistence, so failed credentials/reachability do not leave a dead configured printer;
- Update Printer now performs the same test-before-save check and keeps the previous working configuration if edited host/serial/credentials cannot connect;
- if the persistent replacement adapter cannot connect after an update, FoxForge rolls config/secrets/fleet state back to the previous printer configuration;
- failed Add/Update connection attempts complete durable idempotency as terminal sanitized failures, so a same-key retry replays the same safe error instead of returning `reconciliation_required` or executing the side effect again;
- stable Bambu printer IDs are derived from the normalized serial number;
- Bambu LAN discovery/manual entry and model selection are available from the web UI;
- setup failures use normalized codes rather than raw Python/vendor exceptions;
- EN/RU/UK guidance distinguishes unreachable printer, rejected LAN credentials, MQTT timeout, initial-state timeout and internal adapter failures;
- per-printer reconnect supervision retains secret-safe normalized failure context across recovery;
- the printer **Diagnostics** tab shows reconnect attempts, failure category, retry state and recovery time without exposing raw transport messages or credentials;
- X2D `.3mf` material requirements are inspected before dispatch and explicit physical material bindings are compiled against the live vendor-neutral material topology;
- queue assessment persists the compiler-owned toolhead decision before adapter assessment and repeats routing preparation before a later dispatch;
- the Bambu adapter revalidates source presence, topology freshness and the compiled toolhead from one native snapshot immediately before transport submission;
- complete compiled Bambu routes serialize a per-material `project_file.nozzle_mapping`; partial or unproven nozzle mappings fail closed;
- Bambu external sources 254/255 remain `-1` in flat `ams_mapping`, retain their real source IDs in `ams_mapping2`, and obtain a nozzle only from the proven toolhead route;
- the queue UI now inspects staged 3MF print plans, requires explicit operator material-source bindings, shows compatibility/route blockers and never sends a client-owned toolhead decision;
- Bambu discovery can suggest bounded server-visible RFC1918 subnets, while keeping manual CIDR entry and the same authenticated discovery/preflight boundary;
- Printer Detail now renders typed Material Topology routes with friendly source/toolhead labels and explicit `fixed`, `dynamic`, `unknown` and stale states instead of inferring routing from a Bambu model name;
- EN/RU/UK localization and responsive acceptance now cover the approved 390x844, 900x1024, 1920x1080 and 5120x1440 interface targets;
- FoxForge does not auto-pick a spool by material/color and does not guess a left/right nozzle when routing is ambiguous;
- existing live Bambu state, AMS/AMS 2 Pro material observation and guarded Pause/Resume/Cancel remain available for physical validation.

P3 automatic filament accounting remains frozen during this milestone.

## Write access on Umbrel

FoxForge keeps application authorization separate from Umbrel App Proxy authentication. The package passes Umbrel's unique `APP_PASSWORD` into the container as `FOXFORGE_COMMAND_TOKEN`.

To use protected actions such as **Add Printer**, inventory mutations, queue mutations or Pause/Resume/Cancel:

1. open the FoxForge app through Umbrel;
2. choose **Unlock writes** in FoxForge;
3. enter the FoxForge app password shown by Umbrel (`APP_PASSWORD`);
4. FoxForge keeps that credential only in JavaScript memory for the current tab and sends it as a Bearer token for protected commands;
5. re-enter it after a page reload/tab restart, or after explicitly locking writes.

Umbrel App Proxy remains defense in depth; it is not treated as the FoxForge application principal. Direct backend access without the correct token fails closed for protected commands.

## First start

Install **FoxForge** from this Community App Store and open it once. The server creates and maintains:

- `data/config.json` — persistent non-secret printer connection configuration;
- `data/secrets.json` — application-owned secret store for Bambu LAN access codes and Moonraker API keys;
- `data/foxforge.sqlite3` — durable queue, inventory, command-idempotency and audit state;
- `data/artifacts/` — content-addressed staged `.gcode` / `.3mf` payloads after files are uploaded through the print workflow.

Use **Add Printer** in the FoxForge web UI to configure supported printers. Do not manually place credentials in `config.json`; current FoxForge persists Bambu access codes and Moonraker API keys through its SecretStore boundary. Legacy inline credentials are migrated into `secrets.json` on startup. The complete `/data` directory is credential-bearing data and must be treated as sensitive.

## Bambu Lab LAN setup

Use **Add Printer → Bambu Lab (LAN mode)**. You can scan an explicit local subnet or enter the printer manually. FoxForge asks for:

- display name;
- Bambu model;
- printer serial number;
- printer IP/hostname;
- LAN access code.

FoxForge normalizes the serial number and creates the stable local printer ID automatically. Before saving, it must connect to MQTT and receive an initial live printer state. A failed validation is not persisted. Editing an existing printer follows the same rule: a failed validation leaves the previous working configuration intact.

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

Current FoxForge applies explicit destination/redirect/address-resolution policy to Moonraker endpoints.

## Mixed fleet

Bambu and Moonraker printers can coexist in the same FoxForge instance. `printerId` values must remain unique and stable.

A printer that is powered off or temporarily unreachable does not prevent FoxForge from starting. Per-printer reconnect supervision retries independently with bounded backoff/jitter. Open the printer's **Diagnostics** tab to inspect the normalized reconnect history without exposing raw vendor errors.

## Safe print workflow

For supported print files the browser workflow is intentionally staged:

1. select a local `.gcode` or `.3mf` file;
2. FoxForge calculates SHA-256 in the browser and uploads file bytes only;
3. the backend verifies and stores the content-addressed artifact under `/data/artifacts`;
4. for a routed Bambu `.3mf`, FoxForge inspects the immutable staged artifact, exposes its material requirements and requires explicit physical source bindings;
5. FoxForge compiles each binding against current material-system/topology snapshots and persists the proven toolhead route before adapter assessment;
6. enqueue the artifact for a selected printer;
7. press **Start** separately to dispatch the print;
8. immediately before Bambu submit, FoxForge revalidates that the selected source is still present, topology is current and the compiled source→toolhead route still holds;
9. only a complete proven route can produce Bambu `ams_mapping` / `ams_mapping2` / `nozzle_mapping` fields;
10. if the remote side effect becomes `INDETERMINATE`, reconcile whether the print started instead of retrying blindly.

The client filesystem path is never sent as a server-side path, receipt-bearing jobs are never blindly redispatched, and routing ambiguity is a blocker rather than an invitation to choose a source or nozzle heuristically.

## Pre-Alpha 5 physical validation sequence

Candidate 4 must not be promoted to final Alpha 5 based only on Store CI. On the real Raspberry Pi 5/Umbrel + X2D + AMS 2 Pro deployment, validate at minimum:

1. install/update this exact digest-pinned package and unlock writes using the app password shown by Umbrel;
2. add the X2D through the GUI with its real serial, host and LAN access code;
3. confirm live connection/state and AMS 2 Pro slots/material state, including the two external feed sources when reported;
4. edit one connection field to an intentionally invalid value and confirm the update fails without replacing the working saved printer, then restore the valid form values;
5. retry a failed Add/Update submission without changing its browser command identity when practical and confirm FoxForge returns the same sanitized terminal outcome instead of executing the mutation twice;
6. restart FoxForge and confirm the saved printer reconnects without being re-added;
7. temporarily make the X2D unreachable, confirm a sanitized reconnect incident appears, then restore reachability and confirm recovery;
8. stage a known-safe `.3mf`, inspect its material requirements, explicitly bind each requirement to a currently loaded physical source and review the compiled toolhead/nozzle path;
9. press **Start** separately and verify FTPS upload + MQTT `project_file` acknowledgement on the physical X2D, recording sanitized `ams_mapping`, `ams_mapping2` and `nozzle_mapping` evidence;
10. verify the physical X2D starts exactly one intended job and FoxForge observes the same vendor job/progress;
11. during the test print, verify guarded Pause, Resume and Cancel behavior against the same observed vendor job identity;
12. reload the browser and confirm the operator credential is not retained in browser storage;
13. record failures as well as successes before changing any physical-validation status in the FoxForge repository.

The exact source commit, immutable image digest and Store merge commit must be recorded with the validation evidence. Any implementation change after this candidate invalidates affected physical evidence and requires another immutable candidate.

## Current limitations

- this validation candidate is **not** the final `v0.1.0-alpha.5` release;
- Bambu Virtual Printer is not included;
- automatic queue-to-filament consumption accounting (P3) remains frozen behind the physical/deployment validation gate;
- persistent farm scheduling/distributed leases are not implemented yet;
- deep Bambu AMS/CFS operations such as drying, HMS actions, K profiles and broader FTS controls remain future typed capabilities;
- physical Bambu X2D validation is still required for transport, certificate, material routing, project delivery, job control and lifecycle behavior;
- physical Moonraker/OpenKE validation remains required for endpoint-policy compatibility, upload/start/job-control/lifecycle behavior;
- representative Raspberry Pi 5/UmbrelOS install, restart/persistence, real proxy/write path, printer-network reachability and SSE reconnect/resync validation remain required.

The interface supports English, Russian and Ukrainian.

## Backup and upgrade

Back up the complete FoxForge app `data/` directory before upgrading early alpha versions. Current `/data` contains configuration, SQLite state, staged artifacts and credential-bearing/recovery material, so backups must be treated as sensitive.
