# FoxForge for UmbrelOS

This package installs the immutable FoxForge `v0.1.0-alpha.2` multi-architecture image behind the Umbrel App Proxy and persists all application state under the app data directory.

`alpha.2` is a reliability/UX pre-release: the live interface reports loading, refresh and API failures explicitly, keeps Fleet and Queue read lifecycles independent, and avoids presenting stale/degraded/offline printer telemetry as healthy. It does not add anonymous write APIs or claim completed physical-printer validation.

## First start

Install **FoxForge** from this Community App Store and open it once. The server creates:

- `data/config.json` — printer connection configuration;
- `data/foxforge.sqlite3` — durable queue and filament inventory state.

The alpha UI is read-only for printer configuration, so printers are added by editing `data/config.json` and restarting the FoxForge app. Keep access codes and API keys private; they remain inside the FoxForge app data directory and are not returned by the public read API.

## Bambu Lab LAN example

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

FoxForge uses Bambu LAN MQTT on port `8883` and FTPS on port `990` by default. Optional settings include `mqtt_port`, `ftps_port`, `username`, `connect_timeout_seconds`, `command_timeout_seconds`, and `tls_verify`.

## Moonraker / Klipper example

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

Both printer objects can be placed in the same `printers` array. `printerId` values must be unique and stable.

After saving the file, restart FoxForge from Umbrel. A printer that is powered off or temporarily unreachable does not prevent FoxForge from starting; the runtime keeps it offline and retries the connection in the background.

## Alpha limitations

- printer discovery is not included yet;
- Bambu Virtual Printer is not included yet;
- adding/editing printers through the web UI is not included yet;
- the public HTTP API is intentionally read-only until command authentication and authorization are implemented;
- Bambu X2D, Moonraker/OpenKE and representative Raspberry Pi 5/UmbrelOS physical validation remain separate alpha validation gates.

The interface supports English, Russian and Ukrainian.
