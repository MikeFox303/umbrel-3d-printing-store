# FilaMan managed Bambuddy 1.3.10 release

Physical X2D acceptance exposed a SQLAlchemy `MissingGreenlet` failure after a valid `spool_usage_logged` event reached FilaMan. The Bambuddy plugin consumption writer was changed to load spools through the async-safe `SpoolService.get_spool()` path and keep retries idempotent through the existing `source_event_key`.

Release provenance:

- Bambuddy plugin version: `1.3.10`
- Plugin source release commit: `477c0356285d62d5e1f1a3eb9cee88e2d73bcf00`
- Managed ZIP SHA256: `5aabadc617c85cbe0d4bc0c5c13fe88820ee5cee5174a3455f4e6e3489c4c227`
- FilaMan source commit: `c463135e3eabc9f17e809f74d692b78bfb13dc56`
- FilaMan image tag: `1.2.42-localized.65`
- FilaMan multi-arch digest: `sha256:1e85b72334bce28861f7106f05c55887abc734889739f66f9b6f0cd6ec85ace4`
- Platforms verified before Store pin: `linux/amd64`, `linux/arm64`

The image remains pinned by digest in `my3d-filaman/docker-compose.yml`. Persistent application data remains mounted at `/app/data`; this release does not change ports, environment variables, app proxy settings, or persistent volume layout.
