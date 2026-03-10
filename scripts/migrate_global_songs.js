/*
 * Migration script: team songs -> global songs
 *
 * Prereqs:
 * 1) export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
 * 2) export MIGRATION_PROJECT_ID=<firebase-project-id>
 * 3) export MIGRATION_CONFIRM_PROJECT=<same-project-id>
 * 4) DRY_RUN=1 node scripts/migrate_global_songs.js
 *
 * Optional env:
 *  - DRY_RUN=1 (default, no writes)
 *  - DRY_RUN=0 (enable writes)
 */

const admin = require('firebase-admin');

const credentialsPath = (process.env.GOOGLE_APPLICATION_CREDENTIALS || '').trim();
const projectId = (process.env.MIGRATION_PROJECT_ID || '').trim();
const confirmProjectId = (process.env.MIGRATION_CONFIRM_PROJECT || '').trim();
const dryRun = process.env.DRY_RUN !== '0';

function fail(message) {
  console.error(`[migration-preflight] ${message}`);
  process.exit(1);
}

if (!credentialsPath) {
  fail('GOOGLE_APPLICATION_CREDENTIALS is required.');
}
if (!projectId) {
  fail('MIGRATION_PROJECT_ID is required.');
}
if (!confirmProjectId) {
  fail('MIGRATION_CONFIRM_PROJECT is required.');
}
if (projectId !== confirmProjectId) {
  fail(
    `Project confirmation mismatch: MIGRATION_PROJECT_ID=${projectId}, MIGRATION_CONFIRM_PROJECT=${confirmProjectId}`
  );
}

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  projectId,
});

const db = admin.firestore();
const bucket = admin.storage().bucket();

const normalize = (title) => title.trim().toLowerCase();

async function main() {
  console.log('[migration-preflight] credentials path:', credentialsPath);
  console.log('[migration-preflight] project id:', projectId);
  console.log('[migration-preflight] mode:', dryRun ? 'DRY_RUN=1' : 'DRY_RUN=0');

  const teamsSnap = await db.collection('teams').get();
  const globalIndex = new Map();

  // Preload existing global songs by title
  const globalSnap = await db.collection('songs').get();
  globalSnap.forEach((doc) => {
    const data = doc.data();
    if (data.title) {
      globalIndex.set(normalize(data.title), doc.id);
    }
  });

  console.log(`Found ${teamsSnap.size} teams`);

  for (const teamDoc of teamsSnap.docs) {
    const teamId = teamDoc.id;
    console.log(`\nTeam: ${teamId}`);

    const teamSongsSnap = await db
      .collection('teams')
      .doc(teamId)
      .collection('songs')
      .get();

    for (const songDoc of teamSongsSnap.docs) {
      const data = songDoc.data();
      const title = data.title || '';
      const key = normalize(title);
      if (!title) continue;

      let globalSongId = globalIndex.get(key);

      if (!globalSongId) {
        if (!dryRun) {
          const created = await db.collection('songs').add({
            title: data.title,
            aliases: data.aliases || [],
            tags: data.tags || [],
            searchTokens: data.searchTokens || [],
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            createdBy: data.createdBy || 'migration',
          });
          globalSongId = created.id;
        } else {
          globalSongId = `dry_${songDoc.id}`;
        }
        globalIndex.set(key, globalSongId);
        console.log(`+ Global song created: ${title} -> ${globalSongId}`);
      } else {
        console.log(`= Global song exists: ${title} -> ${globalSongId}`);
      }

      // Create songRef in team
      const songRefDoc = db
        .collection('teams')
        .doc(teamId)
        .collection('songRefs')
        .doc(globalSongId);

      if (!dryRun) {
        await songRefDoc.set(
          {
            songId: globalSongId,
            title: data.title,
            migratedFromTeamSongId: songDoc.id,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
      }

      // Migrate assets
      const assetsSnap = await db
        .collection('teams')
        .doc(teamId)
        .collection('songs')
        .doc(songDoc.id)
        .collection('assets')
        .get();

      for (const assetDoc of assetsSnap.docs) {
        const asset = assetDoc.data();
        const srcPath = asset.storagePath || '';
        const fileName = asset.fileName || assetDoc.id;
        const destPath = `songs/${globalSongId}/${fileName}`;

        if (!dryRun && srcPath && srcPath !== destPath) {
          try {
            await bucket.file(srcPath).copy(destPath);
          } catch (err) {
            console.error(`! Storage copy failed: ${srcPath} -> ${destPath}`, err);
          }
        }

        if (!dryRun) {
          await db
            .collection('songs')
            .doc(globalSongId)
            .collection('assets')
            .doc(assetDoc.id)
            .set(
              {
                ...asset,
                storagePath: destPath,
                migratedFromTeamId: teamId,
                migratedFromSongId: songDoc.id,
              },
              { merge: true }
            );
        }
      }
    }
  }

  console.log('\nMigration complete.');
  if (dryRun) {
    console.log('Dry run mode: no writes were performed.');
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
