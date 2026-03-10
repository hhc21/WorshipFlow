# Global Songs Migration

This script migrates team-level songs into the global `songs` collection and creates
`teams/{teamId}/songRefs/{songId}` references. It also copies storage assets into
`songs/{songId}/...` paths.

## Prereqs
1) Place service account JSON outside this repository (workspace 상주 금지)
2) Export credentials and explicit project guards

```bash
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
export MIGRATION_PROJECT_ID=<firebase-project-id>
export MIGRATION_CONFIRM_PROJECT=<firebase-project-id>
```

## Dry run (no writes)
```bash
DRY_RUN=1 node scripts/migrate_global_songs.js
```

## Run migration
```bash
DRY_RUN=0 node scripts/migrate_global_songs.js
```

## Notes
- Team-level `teams/{teamId}/songs` remain read-only in rules.
- Storage files are copied to `songs/{songId}/...`.
- `MIGRATION_PROJECT_ID` and `MIGRATION_CONFIRM_PROJECT` must be identical or the script exits.
- Default mode is dry-run. Writes are enabled only with `DRY_RUN=0`.
- Key rotation/revocation procedure: `docs/security_key_rotation_runbook.md`.
