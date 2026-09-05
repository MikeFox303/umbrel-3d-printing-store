# FoxForge for UmbrelOS

This package installs the immutable FoxForge `v0.1.0-alpha.4` multi-architecture image behind the Umbrel App Proxy and persists all application state under the app data directory.

`alpha.4` includes authenticated printer setup and queue/inventory commands, common Pause/Resume/Cancel controls for Bambu and Moonraker, FoxForge-owned realtime application events over SSE, the complete normal inventory operator workflow, persistence migrations, SecretStore-backed printer credentials and the independent-audit stabilization/security foundation.

This remains an early alpha. Automated package/runtime checks do not replace representative physical validation on Bambu X2D, Moonraker/OpenKE or Raspberry Pi 5/UmbrelOS.

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

- `data/config.json` — persistent printer connection configuration;
- `data/foxforge.sqlite3` — durable queue, inventory, command-idempotency and audit state;
- `data/artifacts/` — content-addressed staged `.gcode` / `.3mf` payloads after files are uploaded through the print workflow.

Use **Add Printer** in the FoxForge web UI to configure supported printers. Stored access codes and API keys remain inside the FoxForge app data directory and are not returned by public read models. Direct editing of `data/config.json` remains an administrative fallback; stop FoxForge before editing it manually and keep a complete backup of `/data` before alpha upgrades.

## Bambu Lab LAN example

The UI supports the Bambu LAN adapter. The equivalent persisted configuration is:

```json
{
  "schemaVersion": 1,
  "printers": [
    {
      "printerId": "bambu-x2d",
      "displayName": "Bambu Lab X2D",
      "vendor": "Bambu Lab",
      "model": "X2D",
      "serialNumber": "YOUR_PRINTER_SERIAL",
      "adapterKind": "bambu",
      "settings": {
        "host": "192.168.1.100",
        "access_code": "YOUR_LAN_ACCESS_CODE"
      }
    }
  ]
}
```

FoxForge uses Bambu LAN MQTT on port `8883` and implicit FTPS on port `990` by default. Optional settings include `mqtt_port`, `ftps_port`, `username`, `connect_timeout_seconds`, `command_timeout_seconds`, `tls_verify`, and independent MQTT/FTPS certificate SHA-256 pins.

## Moonraker / Klipper example

The UI also supports Moonraker/Klipper configuration. The equivalent persisted configuration is:

```json
{
  "schemaVersion": 1,
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

If Moonraker requires authentication, add `"api_key": "YOUR_API_KEY"` to `settings`. `request_timeout_seconds` is also optional. Current FoxForge applies explicit destination/redirect/address-resolution policy to Moonraker endpoints.

## Mixed fleet

Bambu and Moonraker printers can coexist in the same FoxForge instance. `printerId` values must remain unique and stable.

A printer that is powered off or temporarily unreachable does not prevent FoxForge from starting; per-printer reconnect supervision keeps it offline and retries independently in the background.

## Safe print workflow

For supported print files the browser workflow is intentionally staged:

1. select a local `.gcode` or `.3mf` file;
2. FoxForge calculates SHA-256 in the browser and uploads file bytes only;
3. the backend verifies and stores the content-addressed artifact under `/data/artifacts`;
4. enqueue the artifact for a selected printer;
5. press **Start** separately to dispatch the print;
6. if the remote side effect becomes `INDETERMINATE`, reconcile whether the print started instead of retrying blindly.

The client filesystem path is never sent as a server-side path, and receipt-bearing jobs are never blindly redispatched.

## What alpha.4 adds over the previous Umbrel package

- common typed Pause / Resume / Cancel for Bambu and Moonraker with exact observed vendor-job identity guards;
- realtime SSE invalidation with replay/resync semantics while HTTP snapshots remain canonical truth;
- complete normal inventory workflow: create, correct mass, edit empty-spool mass, assign/move/unassign, archive and inspect history;
- atomic/idempotent inventory persistence;
- versioned persistence migrations and backup/validation machinery;
- SecretStore boundary for Bambu access codes and Moonraker API keys;
- hardened Bambu certificate-pinning option and Moonraker endpoint policy;
- artifact quota/free-space/orphan cleanup;
- per-printer reconnect supervision;
- production-container browser acceptance and stronger dependency/security governance.

## Alpha limitations

- printer discovery is not included yet;
- Bambu Virtual Printer is not included yet;
- automatic queue-to-filament consumption accounting (P3) is not included in `alpha.4` and remains frozen behind the physical/deployment validation gate;
- persistent farm scheduling/distributed leases are not implemented yet;
- deep Bambu AMS/CFS operations, drying, HMS actions, K profiles, dual-nozzle controls and other vendor-depth capabilities remain future typed work;
- physical Bambu X2D validation remains required for transport, certificate, project delivery, job control and lifecycle behavior;
- physical Moonraker/OpenKE validation remains required for endpoint-policy compatibility, upload/start/job-control/lifecycle behavior;
- representative Raspberry Pi 5/UmbrelOS install, restart/persistence, real proxy/write path, printer-network reachability, upgrade and SSE reconnect/resync validation remain required.

The interface supports English, Russian and Ukrainian.

## Backup and upgrade

Back up the complete FoxForge app `data/` directory before upgrading early alpha versions. Current `/data` contains configuration, SQLite state, staged artifacts and credential-bearing/recovery material, so backups must be treated as sensitive.
