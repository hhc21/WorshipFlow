# Global Songs Migration

This script migrates team-level songs into the global `songs` collection and creates
`teams/{teamId}/songRefs/{songId}` references. It also copies storage assets into
`songs/{songId}/...` paths.

## Prereqs
1) Create a Firebase service account key (JSON)
2) Export credentials

```bash
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
```

## Dry run (no writes)
```bash
DRY_RUN=1 node scripts/migrate_global_songs.js
```

## Run migration
```bash
node scripts/migrate_global_songs.js
```

## Notes
- Team-level `teams/{teamId}/songs` remain read-only in rules.
- Storage files are copied to `songs/{songId}/...`.
