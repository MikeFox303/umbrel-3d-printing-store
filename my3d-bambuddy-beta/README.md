# Bambuddy Beta for Umbrel

This package tracks the latest upstream Bambuddy prerelease/daily build selected by the Store automation. The runtime image is always pinned to an immutable multi-architecture digest after CI validation.

Use this package only for testing new Bambuddy features. Before switching from Stable to Beta, create a backup of the Stable data directory. Do not run an older Stable image directly against data that may have been migrated by a newer Beta build.

The planned Bambuddy Manager companion app will automate channel switching, backups, health checks, and rollback.
