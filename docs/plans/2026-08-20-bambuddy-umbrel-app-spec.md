# Bambuddy Umbrel App Specification

## Purpose

Добавить Bambuddy как отдельный production-пакет Community App Store для UmbrelOS на Raspberry Pi 5 без изменения FilaMan.

## Inputs

| Input | Constraints |
| --- | --- |
| Upstream release | Только опубликованный, не draft и не prerelease GitHub Release `maziggy/bambuddy`. |
| Docker image | Только `ghcr.io/maziggy/bambuddy:<version>@sha256:<digest>`; manifest index обязан содержать `linux/arm64`. |
| Sync arguments | Версия `v?X.Y.Z...` без `beta`, `daily`, `nightly`, `dev` или `main`; digest `sha256:` с 64 hex-символами. |

## Outputs

| Scenario | Output |
| --- | --- |
| Package installation | `my3d-bambuddy` behind Umbrel app proxy on port 8280; Bambuddy listens internally on 8000. |
| Data persistence | `${APP_DATA_DIR}/data` maps to `/app/data`; `${APP_DATA_DIR}/logs` maps to `/app/logs`. |
| Stable upstream update | Workflow resolves an ARM64 multi-platform image and changes only Bambuddy compose and manifest files, then commits only if a diff exists. |
| Invalid sync input or unexpected file structure | Script exits non-zero without modifying files. |

## Behavior

1. `docker-compose.yml` uses bridge networking, does not publish Bambuddy port directly, and does not grant host networking, Docker socket, privileged mode, or virtual-printer capabilities.
2. The app proxy forwards to `my3d-bambuddy_server_1:8000` and leaves Bambuddy's own authentication/API key flow available to FilaMan.
3. The README documents manual X2D setup by LAN IP, limits of bridge-mode discovery, physical-device test boundaries, AMS/camera verification, PWA, Tailscale, backups, updates, uninstall, and FilaMan as inventory source where supported.
4. The workflow runs every six hours and manually; it rejects prereleases and image manifests without ARM64 before mutation.
5. No FilaMan files, FilaMan workflow, credentials, databases, archives, or user configuration enter this change.

## Edge Cases

| Case | Expected behavior |
| --- | --- |
| GitHub release is draft/prerelease | Skip it. |
| Docker tag cannot be safely derived or image does not exist | Fail before mutation. |
| Manifest lacks `linux/arm64` | Fail before mutation. |
| Current package already uses the version and digest | No diff and no commit. |
| Compose or manifest image/version format has drifted | Script fails loudly. |
| Physical X2D, AMS 2 Pro, or camera is unavailable | Document as `NOT TESTED`; never report PASS. |

## Acceptance Criteria

- [ ] Store contains an immutable ARM64-capable Bambuddy package with ID `my3d-bambuddy` and port 8280.
- [ ] Package state uses `${APP_DATA_DIR}` data/log mounts and bridge networking only.
- [ ] A tested Node sync script refuses invalid values and updates only Bambuddy package files.
- [ ] A separate workflow uses only stable releases, validates ARM64, avoids empty commits, and leaves FilaMan untouched.
- [ ] Russian documentation accurately labels upstream-dependent X2D, AMS, camera, WebSocket, and FilaMan integration status.
- [ ] YAML and JavaScript validation succeeds; a fresh diff shows no FilaMan changes.

## Explicitly Excluded

- Host networking and automatic SSDP discovery.
- Virtual Printer / Proxy Mode ports and privileges.
- Orca/Bambu slicer sidecars.
- Real-device PASS claims, port forwarding, and committed credentials.
