# FoxForge for UmbrelOS

This package installs the immutable FoxForge `v0.1.0-alpha.3` multi-architecture image behind the Umbrel App Proxy and persists all application state under the app data directory.

`alpha.3` is the first guarded command-capable FoxForge pre-release. In addition to the live fleet, queue and inventory read models, the web application can now manage printer configuration, mutate filament inventory and submit print jobs through authenticated/idempotent command APIs. Print submission remains intentionally explicit and fail-closed: the browser stages file bytes, enqueues the verified artifact and requires a separate Start action; ambiguous `INDETERMINATE` starts require reconciliation instead of blind retry.

## First start

Install **FoxForge** from this Community App Store and open it once. The server creates and maintains:

- `data/config.json` — persistent printer connection configuration;
- `data/foxforge.sqlite3` — durable queue, inventory, command-idempotency and audit state;
- `data/artifacts/` — content-addressed staged `.gcode` / `.3mf` payloads after files are uploaded through the print workflow.

Use **Add Printer** in the FoxForge web UI to configure supported printers. Stored access codes and API keys remain inside the FoxForge app data directory and are not returned by public read models. Direct editing of `data/config.json` remains an administrative fallback; stop FoxForge before editing it manually and keep a backup of `/data` before alpha upgrades.

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

FoxForge uses Bambu LAN MQTT on port `8883` and implicit FTPS on port `990` by default. Optional settings include `mqtt_port`, `ftps_port`, `username`, `connect_timeout_seconds`, `command_timeout_seconds`, and `tls_verify`.

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

If Moonraker requires authentication, add `"api_key": "YOUR_API_KEY"` to `settings`. `request_timeout_seconds` is also optional.

## Mixed fleet

Bambu and Moonraker printers can coexist in the same FoxForge instance. `printerId` values must remain unique and stable.

A printer that is powered off or temporarily unreachable does not prevent FoxForge from starting; the runtime keeps it offline and retries connectivity in the background. Printer setup also exposes test/reconnect actions so configuration can be validated without exposing stored credentials through the read API.

## Safe print workflow

For supported print files the browser workflow is intentionally staged:

1. select a local `.gcode` or `.3mf` file;
2. FoxForge calculates SHA-256 in the browser and uploads file bytes only;
3. the backend verifies and stores the content-addressed artifact under `/data/artifacts`;
4. enqueue the artifact for a selected printer;
5. press **Start** separately to dispatch the print;
6. if the remote side effect becomes `INDETERMINATE`, reconcile whether the print started instead of retrying blindly.

The client filesystem path is never sent as a server-side path, and receipt-bearing jobs are never blindly redispatched.

## Alpha limitations

- printer discovery is not included yet;
- Bambu Virtual Printer is not included yet;
- common Pause / Resume / Cancel controls are not included in `alpha.3`;
- realtime WebSocket/SSE application-event delivery is not implemented yet; the UI still polls;
- automatic queue-to-filament consumption accounting and persistent farm scheduling are not implemented yet;
- deep Bambu AMS operations/drying, HMS actions, K profiles, dual-nozzle controls and X2D-specific storage behavior remain future validated capabilities;
- physical Bambu X2D, Moonraker/OpenKE and representative Raspberry Pi 5/UmbrelOS validation remain separate alpha validation gates.

The interface supports English, Russian and Ukrainian.
