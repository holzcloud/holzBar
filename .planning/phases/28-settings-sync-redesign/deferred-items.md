
## From 28-05

- ~~`holzBar/Core/Sync/SyncReplica.swift:28`: SwiftLint `void_function_in_ternary`~~ Fixed on 2026-10-08.

## From orchestrator verification (2026-10-09)

- `Scripts/check-sync-app.sh` is load-sensitive: on a machine at load 8 to 40 it failed in 6 of 8 runs at different steps (also on the 28-15 tip, so not caused by 28-16), and passed on a quiet machine and in the agents' runs. Its waits (`spin(15)`) are too short under heavy load. Before plan 28-18 flips the pause: re-run it on a quiet machine, and raise the waits or make them condition-based.
