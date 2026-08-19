# Bambuddy Umbrel App Implementation Plan

> **For Codex:** Execute this plan task-by-task with verification after each task.

**Goal:** Package stable Bambuddy for the existing `my3d` Umbrel Community Store without changing FilaMan.

**Architecture:** Mirror the existing FilaMan package for manifest, proxy, immutable image, and sync-script conventions. Bambuddy runs its official image in Docker bridge mode; Umbrel app proxy exposes it at port 8280 while data and logs persist under `APP_DATA_DIR`.

**Tech Stack:** Umbrel manifest/Compose YAML, GitHub Actions, Node.js ESM, GitHub Releases API, Docker Buildx in CI.

---

### Task 1: Add an executable, validated update path

**Files:**
- Create: `scripts/sync-bambuddy-release.mjs`
- Create: `tests/sync-bambuddy-release.test.mjs`

**Steps:**
1. Write Node tests for valid stable versions/digests, forbidden prerelease strings, unchanged values, and unexpected image formats.
2. Run `node --test tests/sync-bambuddy-release.test.mjs`; observe failures because the implementation does not exist.
3. Implement strict argument validation and anchored substitutions scoped to the two Bambuddy files.
4. Re-run the tests; expect all tests to pass.

### Task 2: Add the immutable Bambuddy package

**Files:**
- Create: `my3d-bambuddy/docker-compose.yml`
- Create: `my3d-bambuddy/umbrel-app.yml`
- Create: `my3d-bambuddy/data/.gitkeep`
- Create: `my3d-bambuddy/logs/.gitkeep`

**Steps:**
1. Use version `1.2.5.3` and digest `sha256:c670164aaa3b0c5af715ca00e9745cdf3a4d7d337fc11d96fc85180371952698` from the verified OCI index.
2. Mirror the FilaMan package shape, adapting only the proxy host, port 8280, Bambuddy image, environments, and storage mounts.
3. Validate the compose configuration where Docker is available and parse both YAML files.

### Task 3: Add stable-release synchronization

**Files:**
- Create: `.github/workflows/sync-bambuddy.yml`

**Steps:**
1. Mirror the independent FilaMan workflow shape.
2. Resolve the latest non-draft, non-prerelease release, normalize its tag, reject unsafe values, inspect the multi-platform image, require ARM64, and call the sync script.
3. Stage only Bambuddy compose and manifest files and skip an empty commit.
4. Parse workflow YAML and compare it with `sync-filaman.yml` to ensure it is unchanged.

### Task 4: Document safe operation

**Files:**
- Create: `my3d-bambuddy/README.md`
- Modify: `README.md`
- Modify: `.gitignore`

**Steps:**
1. Document upstream-supported local developer mode, bridge-mode manual setup, device-data secrecy, camera/AMS validation limits, PWA/Tailscale, backup/restore precautions, and FilaMan API setup without credentials.
2. Extend the root store README without removing FilaMan guidance.
3. Add ignores for databases, archives, environments, and Bambuddy data/log contents while preserving `.gitkeep`.
4. Search staged text for credential-like values and confirm only placeholder/documentation references remain.

### Task 5: Verify scope and package integrity

**Files:**
- Verify: all Bambuddy files, `my3d-filaman/**`, `.github/workflows/sync-filaman.yml`

**Steps:**
1. Run Node tests, syntax checks, YAML parse checks, image-reference/digest checks, and `git diff --check`.
2. If Docker remains unavailable locally, report `docker compose config` and Buildx inspection as not locally runnable; CI includes Buildx inspection.
3. Run `git diff -- my3d-filaman` and `git diff -- .github/workflows/sync-filaman.yml`; expect empty output.
4. Review the full diff and produce the required change walkthrough before any commit.
