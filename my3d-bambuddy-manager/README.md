# Bambuddy Manager

Companion Umbrel app for managing the Bambuddy runtime channel without modifying upstream `maziggy/bambuddy`.

## Manager 0.2

- reads and validates Store-approved `stable` and `beta` channel metadata;
- requires immutable official `ghcr.io/maziggy/bambuddy:*@sha256:...` references;
- requires channel metadata to have passed both `linux/amd64` and `linux/arm64` Store validation;
- distinguishes the Umbrel bootstrap package version from the actual Bambuddy runtime version;
- supports Stable -> Beta, Beta -> Stable and in-channel Stable/Beta updates;
- stops Bambuddy before creating a transaction snapshot;
- uses Python/SQLite's backup API instead of copying a live database file;
- supports both `bambuddy.db` and `bambutrack.db` when present;
- runs SQLite `PRAGMA integrity_check` and records SHA-256 checksums for database and compose snapshots;
- records ownership/mode metadata and restores it where the host permits;
- preserves a Stable snapshot while a machine is in Beta;
- restores that Stable snapshot before Beta -> Stable so an older schema is never intentionally opened against Beta-only database migrations;
- persists an unfinished transaction record before destructive container replacement;
- can recover an unfinished transaction after a Manager/browser interruption;
- health-checks the target runtime and verifies the running container references the expected immutable image;
- automatically rolls back a failed switch;
- exposes a manual rollback to the most recent verified snapshot and creates a reverse snapshot first;
- retains recent snapshots while protecting snapshots referenced by active rollback state;
- keeps Docker control in the Manager container instead of exposing `/var/run/docker.sock` to Bambuddy itself.

## Runtime ownership

Bambuddy itself remains the normal Umbrel app and uses the official upstream image. The version packaged in `my3d-bambuddy` is a tested **bootstrap runtime**.

After Manager is installed, channel automation publishes only:

- `channels/bambuddy/stable.json`
- `channels/bambuddy/beta.json`

The Stable/Beta automation does **not** rewrite the installed Bambuddy Umbrel package. This avoids having two independent update systems changing the runtime while a Beta rollback point exists.

A channel update is therefore:

```text
upstream release / daily
        |
        v
Store CI: resolve immutable digest
        |
        +-- amd64 smoke test
        +-- arm64 smoke test
        +-- APP_VERSION check
        +-- post-test upstream revalidation
        |
        v
channel JSON
        |
        v
Bambuddy Manager
        |
        +-- verified snapshot
        +-- container replacement
        +-- health check
        +-- rollback/recovery
```

## Container recreation policy

Manager intentionally does **not** copy the previous image's `Cmd`, `Entrypoint`, `Healthcheck`, `WorkingDir` or image-default environment into the new container. Those defaults belong to the target Bambuddy image and may legitimately change between releases.

Manager parses the installed `server.environment` section and carries over only values explicitly supplied by the Umbrel Compose configuration. It also preserves the required host configuration such as binds, host networking, restart policy, capabilities, extra hosts and init setting.

If the installed Bambuddy Compose contains unsupported service overrides (`command`, `entrypoint`, `user`, `working_dir`, `hostname`, `domainname` or `healthcheck`), Manager refuses the switch rather than guessing how to reproduce it safely.

## Snapshot model

Every destructive runtime operation begins with a snapshot under the Manager's private data directory. A snapshot contains:

- SQLite backup(s), currently `bambuddy.db` and/or `bambutrack.db`;
- the installed Bambuddy `docker-compose.yml`;
- an immutable Bambuddy image reference;
- SHA-256 checksums;
- SQLite integrity verification result (the snapshot is rejected unless it is `ok`);
- database ownership/mode metadata.

Snapshot paths are resolved and required to remain below the Manager backup root before restore. The default retention target is 12 unreferenced snapshots; active Stable/last/pending snapshots are protected from pruning.

This transactional snapshot protects the Bambuddy database and runtime definition. It is **not** a replacement for Bambuddy's own full backup when archive/media/library files also need point-in-time recovery.

## Umbrel packaging and security

The Manager uses a pinned multi-architecture official Python image. `server.py.template` is shipped with the Umbrel package and mounted read-only, so no custom Manager runtime image is required.

The Manager has `/var/run/docker.sock`, which is effectively host-administration capability. Therefore:

- Manager must stay behind Umbrel App Proxy authentication;
- do not add `PROXY_AUTH_ADD: "false"`;
- Bambuddy itself does not receive the Docker socket;
- write APIs require an additional Manager request header, which also prevents simple cross-origin form submissions from triggering operations.

The current package targets the confirmed MikeFox Umbrel path `/home/umbrel/umbrel/app-data/my3d-bambuddy`. This assumption is explicit and should be revisited if the Store is later intended for Umbrel installations using a different app-data root.

## Validation

The Store release gate currently covers:

- channel metadata unit tests;
- Manager Python unit tests;
- SQLite snapshot/restore + corruption detection tests;
- package/channel ownership architecture tests;
- Compose validation;
- Manager HTTP startup smoke test;
- a real Docker container recreation smoke test that starts with deliberately overridden old `Entrypoint`/`Cmd`, recreates through Manager, then verifies the new image defaults and `/health`;
- Bambuddy runtime smoke tests on both amd64 and arm64.
