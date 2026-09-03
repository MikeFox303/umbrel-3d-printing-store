# Bambuddy Manager

Companion Umbrel app for managing the Bambuddy runtime channel without modifying upstream `maziggy/bambuddy`.

## Current MVP

- reads Store-approved `stable` and `beta` channel metadata;
- shows the installed immutable Bambuddy image and whether the container is running;
- switches Stable <-> Beta using only Store-tested `image@sha256` references;
- stops Bambuddy before snapshotting SQLite state;
- preserves a Stable snapshot before entering Beta;
- restores that Stable snapshot before a Beta -> Stable downgrade;
- recreates the Bambuddy server container while preserving its existing environment, binds, labels, host networking, capabilities, restart policy and init setting;
- health-checks Bambuddy after switching;
- attempts automatic rollback to the previous image and SQLite snapshot when a switch fails;
- keeps Docker control in the Manager container instead of exposing `/var/run/docker.sock` to Bambuddy itself.

## Umbrel packaging

The Manager uses a pinned multi-architecture official Python image. `server.py.template` is shipped as an Umbrel `*.template` file and mounted read-only into the container so the Manager does not require a separate custom runtime image.

The Manager is intentionally protected by Umbrel App Proxy authentication. Do not add `PROXY_AUTH_ADD: "false"` to this app: access to the Manager is equivalent to privileged Docker administration.

## Safety notes

The current switch transaction snapshots the default SQLite database (`bambuddy.db` plus WAL/SHM files when present) and the installed Bambuddy compose file. This is specifically intended to make schema rollback safe when testing Beta builds. It is not a replacement for Bambuddy's own full backup feature, which can include all stateful directories.

The current package targets the standard MikeFox Umbrel installation path `/home/umbrel/umbrel/app-data/my3d-bambuddy`. A later hardening pass should discover the sibling app-data path instead of assuming it.
