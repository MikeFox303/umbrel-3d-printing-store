# Bambuddy channels and Manager implementation plan

Tracking: #10

This branch introduces Umbrel-side Bambuddy release channels without modifying upstream `maziggy/bambuddy`.

## Goals

- Keep Stable on immutable, tested upstream digests.
- Add Beta/Daily as a separately resolved, immutable, tested channel.
- Add an Umbrel `Bambuddy Manager` companion app for status, channel switching, backup and rollback.
- Preserve the existing Bambuddy data directory and host-network Virtual Printer configuration.
- Never expose the Docker socket to the Bambuddy application itself.

## Delivery order

1. Channel metadata and beta sync workflow.
2. Shared tests/guards for stable and beta packages.
3. Minimal Manager service + UI.
4. Safe switch transaction: stop, backup, switch, health-check, rollback on failure.
5. Upgrade/downgrade compatibility documentation and recovery procedure.

## Safety model

The Store continues to publish exact `image@sha256:digest` references. Rolling tags are only discovery inputs in CI. Stable/Beta switching must create a data snapshot first. A downgrade must restore the snapshot associated with the target stable runtime instead of blindly running an older image against a database already migrated by beta.
