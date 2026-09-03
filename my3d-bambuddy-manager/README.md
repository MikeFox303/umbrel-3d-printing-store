# Bambuddy Manager

Companion Umbrel app for managing the Bambuddy runtime channel without modifying upstream Bambuddy.

Planned responsibilities:

- display installed Stable/Beta versions and immutable digests;
- switch between Stable and Beta/Daily;
- create snapshots before every channel transition;
- health-check the target runtime;
- rollback automatically on a failed transition;
- provide an explicit restore path for Beta -> Stable downgrades;
- keep Docker control isolated from the Bambuddy application container.

The first implementation milestone will expose a local-only management UI and a narrow update agent API.
