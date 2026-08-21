# X2D Cloud integration release — 2026-08-21

This record pins the artifacts used for the Bambu Lab X2D Cloud-mode consumption acceptance release.

## Immutable artifacts

### Bambuddy

- Source: `MikeFox303/bambuddy`
- Product source SHA: `c04d1c5e95f3f0640de6db995ee82e00d3cf3271`
- Image: `ghcr.io/mikefox303/bambuddy:1.2.5.3-test.x2d-cloud.2`
- OCI index digest: `sha256:9b3d3b95112e6923a246cf7f7acc8ef09ffbd1164ac632fd2e243433d9cc161f`
- Platforms: `linux/amd64`, `linux/arm64`

### FilaMan

- Source: `MikeFox303/filaman-system`
- Product source SHA: `22a3e8ca3e841e2debe20f473db036f1549735f0`
- Image: `ghcr.io/mikefox303/filaman-system:1.2.42-localized.32`
- OCI index digest: `sha256:bf06d061523d0500a04c58eef5aef176ca2ec0b47b99848cccc113c2b3c4e384`
- Platforms: `linux/amd64`, `linux/arm64`
- Managed Bambuddy plugin: `1.3.8`
- Managed plugin ZIP SHA256: `a41f6bd38f9ebce1f21b620f9ce7ea8ab3984fc2a633cffe18e33518e906d508`

The OCI digests and platform lists above were recovered from the BuildKit `.dockerbuild` records emitted by the successful image push steps, so the Store is pinned to the exact published multi-architecture indexes.

## Deployment order

1. Back up the persistent FilaMan database and record its checksum.
2. Update Bambuddy first and confirm that it starts normally.
3. Update FilaMan second. On startup it installs/upgrades the managed Bambuddy plugin to 1.3.8 before printer drivers start.
4. Keep the X2D printer integration in `inventory_only` write mode for Cloud-mode acceptance.
5. Perform a one-spool consumption print, then a multi-spool print, and verify exactly one deduction per source event.

`TEST_PIN` intentionally remains present with value `x2d-cloud-final`; the scheduled upstream image-sync workflows must not replace these immutable custom pins during acceptance.

## Rollback

- Bambuddy known upstream fallback: `ghcr.io/maziggy/bambuddy:1.2.5.3@sha256:c670164aaa3b0c5af715ca00e9745cdf3a4d7d337fc11d96fc85180371952698`.
- Prefer rolling back Bambuddy independently if FilaMan itself is healthy.
- Do not downgrade FilaMan without a database backup and schema-compatibility check. Restoring the pre-update database backup is the safest full rollback path.
