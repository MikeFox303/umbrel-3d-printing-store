# Bambuddy channels and Manager implementation plan

Tracking: #10

This branch introduces Umbrel-side Bambuddy release channels without modifying upstream `maziggy/bambuddy`.

## Goals

- Keep Stable on immutable, tested upstream digests.
- Add Beta/Daily as a separately resolved, immutable, tested channel.
- Add an Umbrel `Bambuddy Manager` companion app for status, channel switching, backup and rollback.
- Preserve the existing Bambuddy data directory and host-network Virtual Printer configuration.
- Never expose the Docker socket to the Bambuddy application itself.
- Keep a single authority for post-install runtime changes: Bambuddy Manager.

## Implemented in this branch

1. Store-owned Stable/Beta channel metadata.
2. Stable discovery from upstream non-prerelease releases.
3. Beta discovery from the upstream daily prerelease + `:daily` image.
4. Immutable digest resolution and amd64/arm64 validation.
5. Runtime `APP_VERSION` verification and post-smoke upstream revalidation to avoid release/image race conditions.
6. Metadata-only Stable/Beta publication; channel workflows do not rewrite the Bambuddy Umbrel package.
7. Bambuddy Manager 0.2 companion app behind Umbrel App Proxy authentication.
8. Stable/Beta and same-channel runtime updates using exact Store-approved image digests.
9. SQLite Backup API snapshots with integrity check, checksums and compose snapshot.
10. Durable pending transaction state, automatic rollback and explicit recovery for interrupted transactions.
11. Manual rollback with a reverse snapshot of the current state.
12. New-image-default container recreation: old image `Cmd`/`Entrypoint` and image-default environment are not frozen into the next runtime.
13. Snapshot retention while preserving active Stable/last/pending rollback references.
14. Unit, Compose, HTTP startup, Docker recreation, amd64 and arm64 runtime validation in the Store gate.

## Safety model

The Store publishes exact `image@sha256:digest` references. Rolling tags are discovery inputs only in CI.

A destructive runtime operation follows this sequence:

```text
validate channel metadata
        |
inspect current container + compose policy
        |
stop Bambuddy
        |
verified SQLite snapshot + compose snapshot
        |
persist pending transaction record
        |
pull immutable target
        |
replace runtime container
        |
health-check + verify expected image
        |
commit state
```

If replacement fails after the pending record is written, Manager restores the pre-operation snapshot and immutable image. If Manager itself is interrupted mid-transaction, the persisted pending record remains visible and can be explicitly recovered.

Beta -> Stable is intentionally different from an ordinary upgrade: the Stable snapshot captured before entering Beta is restored first, so an older Stable schema is not intentionally opened against a Beta-migrated database.

## Runtime ownership decision

`my3d-bambuddy` remains the bootstrap Umbrel package. Its packaged version is not continuously rewritten by Stable automation after this feature is introduced.

New tested upstream releases are published to channel metadata and are applied by Manager. This prevents an ordinary Umbrel package update from bypassing the Manager's Beta rollback state.

## Remaining before declaring 0.2 production-ready

- Complete the final PR release gate with the real Docker recreation test enabled.
- Exercise a real Stable -> Beta -> Stable transaction on the target Umbrel host before enabling Beta for normal use.
- Confirm the fixed `/home/umbrel/umbrel/app-data/my3d-bambuddy` host-path assumption on the target Umbrel installation after merge/install.
- Keep Bambuddy's own full backup as the recommended protection for archives/media; Manager transaction snapshots intentionally focus on database/runtime rollback.
