# Compatibility fixtures

These are synthetic, hand-authored historical formats, independent of the current
serializer. `legacy_split_v1.json` models the three preferences keys before the
atomic snapshot, including the earlier ISO-string reminder timestamp.
`portable_backup_v1.json` models a portable backup with embedded proof bytes.
The expected proof is exactly UTF-8 `proof A\n`.

Keep these files fixed when schemas evolve; add a new fixture for a new format.
Desktop file-store tests cover controller/file boundaries. Actual
SharedPreferences and fresh-engine restart are exercised by `integration_test/`.
