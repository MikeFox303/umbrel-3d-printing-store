# Bambuddy Manager

Companion Umbrel app for managing the Bambuddy runtime channel without modifying upstream `maziggy/bambuddy`.

## Quick Start

1. Install **Bambuddy** (`my3d-bambuddy`) from this Store and verify that it starts normally.
2. Install **Bambuddy Manager** (`my3d-bambuddy-manager`). Umbrel exposes it through App Proxy on port `8282`.
3. Open Manager and review three separate values: the installed Umbrel bootstrap package, the currently running Bambuddy runtime, and the Store-approved Stable/Beta channels.
4. Stay on **Stable** for normal use. Use **Beta** only when you intentionally want to test the validated daily/prerelease channel.
5. Before every destructive switch Manager stops Bambuddy and creates a verified transaction snapshot. Do not manually restart or replace the Bambuddy container while a switch is in progress.
6. A failed target startup or health check triggers automatic rollback. The latest verified snapshot can also be restored manually from Manager.
7. When returning **Beta -> Stable**, Manager restores the protected Stable snapshot before starting the older Stable runtime so a Stable build is not intentionally opened against Beta-only database migrations.

Expected version model:

```text
Umbrel package version = bootstrap/package definition
Bambuddy runtime       = Stable or Beta channel selected by Manager
```

Those versions may differ after a channel switch and that is expected. Channel automation updates only `channels/bambuddy/stable.json` and `channels/bambuddy/beta.json`; it does not rewrite the installed `my3d-bambuddy` package.

### Safety rules for operators

- Keep Manager behind Umbrel App Proxy authentication.
- Do not publish port `8282` directly to the internet.
- Do not give `/var/run/docker.sock` to the Bambuddy container itself.
- Avoid hand-editing Bambuddy `image`, `command`, `entrypoint`, `user`, `working_dir` or `healthcheck` while Manager owns runtime switching. Unsupported overrides cause Manager to refuse the switch instead of guessing.
- Manager snapshots protect SQLite databases and runtime definition; keep normal full Bambuddy backups as well when media, archives or library files also need point-in-time recovery.

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

New Bambuddy packages export both their installed definition directory and their current physical persistent-data directory through `exports.sh`. Umbrel sources dependency exports before Manager's own exports, so Manager prefers those exact paths and follows Bambuddy if its persistent data is relocated to another storage device. For Bambuddy installations created before this dependency contract existed, Manager has a compatibility fallback that derives the sibling `my3d-bambuddy` definition directory from its own `EXPORTS_APP_DIR` and uses the traditional `<app>/data` location. Both paths are mounted with `create_host_path: false`, so an invalid or unavailable path fails explicitly instead of silently creating an empty host directory. No `/home/umbrel/...` or `/state/default/...` host path is hard-coded.

## Validation

The Store release gate currently covers:

- channel metadata unit tests;
- Manager Python unit tests;
- SQLite snapshot/restore + corruption detection tests;
- package/channel ownership architecture tests;
- dynamic Bambuddy dependency path contract tests, including the legacy fallback and relocated-data preservation;
- Compose validation with separate dependency-exported definition/data paths and non-creating bind mounts;
- Manager HTTP startup smoke test;
- a real Docker container recreation smoke test that starts with deliberately overridden old `Entrypoint`/`Cmd`, recreates through Manager, then verifies the new image defaults and `/health`;
- Bambuddy runtime smoke tests on both amd64 and arm64.
