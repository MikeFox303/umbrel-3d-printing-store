# FoxForge for UmbrelOS

This package installs FoxForge behind the Umbrel App Proxy and persists all application state under the app data directory.

The current Store package is **Pre-Alpha 5 physical-validation Candidate 6**, not the final `v0.1.0-alpha.5` release. Candidate 6 is built from FoxForge application source commit `a2a0c54f392de8085a6a9635920a6da465d8fbe8` and is intended for the real Raspberry Pi 5/Umbrel + Bambu X2D + AMS 2 Pro validation path.

The Store version uses the package-local identity `0.1.0-alpha.4.3-umbrel.6`. The `0.1.0-alpha.4.3` base remains tied to the latest published FoxForge release for upstream-version auditing, while `-umbrel.6` identifies the sixth installable physical-validation package. The exact newer source and immutable image digest are recorded separately in the package contract and release notes. This candidate must not be treated as the final Alpha 5 release.

Candidate 5 is **retired for physical acceptance** after the first real X2D connection test. Candidate 1/2/3/4/5 evidence is historical and must not be relabeled or carried across the Candidate 6 digest.

This remains early-alpha software. Automated package/runtime checks do not replace representative physical validation on Bambu X2D, Moonraker/OpenKE or Raspberry Pi 5/UmbrelOS.

## Why Candidate 6 replaces Candidate 5

Candidate 5 proved several important deployment facts on the real installation before failing:

- the FoxForge Docker bridge could scan the real `192.168.0.0/24` LAN without `network_mode: host`;
- discovery found the physical X2D as a Bambu LAN device;
- MQTT transport authentication completed with the real printer credentials;
- authoritative Save-time backend preflight remained fail-closed and did not persist a printer when initial-state validation failed;
- the same physical X2D remained connected and fully usable in Bambuddy, isolating the failure to FoxForge compatibility rather than printer/LAN configuration.

The failure was `initial_state_timeout`: Candidate 5 required the merged state to contain `gcode_state` before considering the Bambu connection usable. Real Bambu telemetry is incremental, so a valid state-bearing `push_status` may omit `gcode_state`. Candidate 6 keeps MQTT CONNACK and `get_version` alone insufficient, but accepts a real non-empty partial `push_status` as initial state.

While comparing the same X2D/H2-family telemetry path with Bambuddy before freezing a new candidate, a second compatibility gap was closed: these dual-external-source printers can report their complete external spool inventory in `vir_slot`. Candidate 6 therefore:

- parses `vir_slot` as the full external-source list when present;
- gives `vir_slot` precedence over legacy/partial `vt_tray` when both are reported;
- preserves legacy `vt_tray` compatibility when `vir_slot` is absent;
- preserves physical source IDs 254 and 255 instead of guessing missing IDs;
- keeps dual-source presentation as **External Left** / **External Right** only when both physical IDs are actually present.

These are newly written FoxForge compatibility changes informed by observed/upstream behavior; no Bambuddy implementation code is copied.

## What this validation candidate includes

Compared with the latest semantic Alpha 4.3 release package, Candidate 6 includes the full Pre-Alpha 5 Bambu connection, routing-safety and interface work merged into FoxForge `main`:

- Add Printer validates a Bambu connection before persistence, so failed credentials/reachability do not leave a dead configured printer;
- Update Printer performs the same test-before-save check and keeps the previous working configuration if edited host/serial/credentials cannot connect;
- failed Add/Update connection attempts complete durable idempotency as terminal sanitized failures, so a same-key retry replays the same safe error instead of executing the side effect again;
- stable Bambu printer IDs are derived from the normalized serial number;
- Bambu LAN discovery/manual entry and model selection are available from the web UI;
- setup failures use normalized codes rather than raw Python/vendor exceptions;
- per-printer reconnect supervision retains secret-safe normalized failure context across recovery;
- the printer **Diagnostics** tab shows reconnect attempts, failure category, retry state and recovery time without exposing credentials;
- X2D `.3mf` material requirements are inspected before dispatch and explicit physical material bindings are compiled against live vendor-neutral material topology;
- queue assessment persists the compiler-owned toolhead decision and repeats routing preparation before dispatch;
- the Bambu adapter revalidates source presence, topology freshness and compiled toolhead from one native snapshot before transport submission;
- complete compiled Bambu routes serialize `project_file.nozzle_mapping`; partial or unproven nozzle mappings fail closed;
- Bambu external sources 254/255 remain `-1` in flat `ams_mapping`, retain their real source IDs in `ams_mapping2`, and obtain a nozzle only from the proven toolhead route;
- FoxForge does not auto-pick a spool by material/color and does not guess a left/right nozzle when routing is ambiguous;
- present-but-invalid project/toolhead metadata emits `TOOLHEAD_METADATA_INVALID`, and a fixed physical source cannot mask corrupt slicer intent;
- selected-plate routing readiness is scoped to the selected plate while global and selected-plate safety blockers remain fail-closed;
- Printer Detail renders typed Material Topology routes with explicit `fixed`, `dynamic`, `unknown` and stale states;
- the application shell, standard printer cards and Control/Materials tabs are capability-driven rather than model-name driven;
- Add Printer is an explicit **Provider → Connection → Identity → Verify** workflow; verification is bound to the exact normalized payload and any later payload change means **Save is disabled again until a new Verify succeeds**;
- the backend repeats authoritative preflight immediately before durable persistence;
- EN/RU/UK localization and responsive acceptance cover 390x844, 900x1024, 1920x1080 and 5120x1440 targets;
- existing live Bambu state, AMS/AMS 2 Pro observation and guarded Pause/Resume/Cancel remain available for physical validation.

P3 automatic filament accounting remains frozen during this milestone.

## Write access on Umbrel

FoxForge keeps application authorization separate from Umbrel App Proxy authentication. The package keeps application write authentication enabled and uses Umbrel's per-app password as the operator credential.

To use protected actions such as **Add Printer**, inventory mutations, queue mutations or Pause/Resume/Cancel:

1. open FoxForge through Umbrel;
2. choose **Unlock writes**;
3. enter the app password shown by Umbrel;
4. the browser keeps the credential only in memory for the current tab;
5. re-enter it after reload/tab restart or after explicitly locking writes.

Umbrel App Proxy remains defense in depth; it is not treated as the FoxForge application principal. Direct backend protected writes without the correct credential fail closed.

## First start and persistence

FoxForge creates and maintains:

- `data/config.json` — persistent non-secret printer configuration;
- `data/secrets.json` — SecretStore for Bambu LAN access codes and Moonraker API keys;
- `data/foxforge.sqlite3` — durable queue, inventory, command-idempotency and audit state;
- `data/artifacts/` — content-addressed staged `.gcode` / `.3mf` payloads.

Use **Add Printer** in the web UI. Do not manually place credentials in `config.json`; current FoxForge stores them in `data/secrets.json`. Treat the complete `/data` directory as sensitive and back it up before early-alpha upgrades.

## Bambu Lab LAN setup

Use **Add Printer → Bambu Lab (LAN mode)**. The staged wizard is **Provider → Connection → Identity → Verify**. You can scan an explicit local subnet or enter the printer manually. FoxForge asks for display name, model, serial number, IP/hostname and LAN access code.

Before saving, the current exact payload must pass Verify. If host, access code, identity, model or another payload field changes after verification, Save is disabled again until a new Verify succeeds. The backend independently repeats preflight before durable persistence. A failed validation is not persisted. Update Printer follows the same test-before-save rule and preserves the prior working configuration on failure.

The resulting non-secret `config.json` shape is equivalent to:

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

The LAN access code is stored separately in `data/secrets.json` and is not returned by public read models. FoxForge uses Bambu MQTT TLS on port `8883` and implicit FTPS on port `990` by default.

## Moonraker / Klipper setup

Use **Add Printer → Klipper / Moonraker** and provide a stable display identity and Moonraker URL. If an API key is required, enter it in the UI; FoxForge stores it through the SecretStore boundary.

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

Current FoxForge applies explicit destination/redirect/address-resolution policy to Moonraker endpoints. Bambu and Moonraker printers may coexist in one instance.

## Safe print workflow

The browser workflow is intentionally staged:

1. select a local `.gcode` or `.3mf`;
2. FoxForge calculates SHA-256 and uploads bytes to content-addressed storage;
3. for routed Bambu `.3mf`, inspect the immutable selected plate/material requirements;
4. bind each logical material explicitly to a current physical source;
5. fail closed on malformed/ambiguous/unsafe slicer toolhead metadata;
6. compile source bindings against current material-system/topology evidence;
7. enqueue only the reviewed intent;
8. press **Start** separately;
9. immediately before submit, revalidate source presence/topology/toolhead;
10. emit `ams_mapping` / `ams_mapping2` / `nozzle_mapping` only from a complete proven route;
11. if a remote side effect becomes `INDETERMINATE`, reconcile instead of blindly retrying.

## Candidate 6 physical validation sequence

Candidate 6 must not be promoted based only on Store CI. On the real Raspberry Pi 5/Umbrel + X2D + AMS 2 Pro deployment:

1. install/update this exact digest-pinned package and verify Candidate 6 identity;
2. unlock writes from the GUI with the app password shown by Umbrel and confirm reload locks writes again;
3. scan the actual private LAN or use manual CIDR, select the physical X2D rather than any proxy/virtual printer, then add the X2D through the staged GUI wizard;
4. after successful Verify, change one field and confirm Save disables until re-verification;
5. confirm Save-time backend preflight succeeds and the physical printer is persisted;
6. confirm live state and material topology: real AMS 2 Pro slots plus both external feed sources when reported; for the current X2D fixture specifically validate `vir_slot`/physical IDs rather than guessing from model name;
7. edit one connection field to an intentionally invalid value and confirm Update fails without replacing the working saved printer;
8. restart FoxForge and confirm automatic reconnect without re-adding the printer;
9. temporarily make X2D unreachable, confirm sanitized reconnect diagnostics, restore reachability and confirm recovery;
10. stage a known-safe `.3mf`, inspect selected plate/material requirements, bind explicit physical sources and verify corrupt/ambiguous selected-plate metadata remains blocked;
11. **only after the complete no-print gate passes**, press **Start** separately and verify FTPS upload + MQTT `project_file` acknowledgement, effective mappings and exactly one intended physical print;
12. verify guarded Pause/Resume/Cancel or completion against the exact observed job.

The exact source commit, immutable digest and Store merge commit must be recorded with evidence. Any application implementation change creates a new evidence boundary and requires another immutable candidate.

## Current limitations

- Candidate 6 is not final `v0.1.0-alpha.5`;
- Bambu Virtual Printer is not included;
- P3 automatic filament accounting remains frozen;
- persistent farm scheduling/distributed leases are not implemented yet;
- deep Bambu AMS/CFS operations such as drying, HMS actions, K profiles and broader FTS controls remain future typed capabilities;
- physical X2D validation is still required for the complete connection, topology, storage, print and job-control lifecycle;
- physical Moonraker/OpenKE validation remains required;
- representative Raspberry Pi 5/Umbrel install/restart/persistence, App Proxy/write path and realtime recovery evidence remain required.

The interface supports English, Russian and Ukrainian.
