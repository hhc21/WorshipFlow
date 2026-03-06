/**
 * Cloud Function PoC: Firestore delete queue worker
 *
 * Target trigger:
 *   teams/{teamId}/deleteQueue/{requestId}
 *
 * This file is intentionally isolated as a PoC artifact (not deployed by default).
 * Deploy path can be moved to real `functions/` once infrastructure is approved.
 */

const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

async function markStatus(ref, status, extra = {}) {
  await ref.set(
    {
      status,
      ...extra,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

async function handleProjectDelete(teamId, projectId) {
  const projectRef = db.collection('teams').doc(teamId).collection('projects').doc(projectId);
  const snapshot = await projectRef.get();
  if (!snapshot.exists) return;
  await db.recursiveDelete(projectRef);
}

async function handleTeamDelete(teamId) {
  const teamRef = db.collection('teams').doc(teamId);
  const snapshot = await teamRef.get();
  if (!snapshot.exists) return;

  const data = snapshot.data() || {};
  const teamNameKey = (data.nameKey || '').toString().trim();
  if (teamNameKey) {
    await db.collection('teamNameIndex').doc(teamNameKey).delete().catch(() => {});
  }
  await db.recursiveDelete(teamRef);
}

exports.processDeleteQueue = onDocumentCreated(
  'teams/{teamId}/deleteQueue/{requestId}',
  async (event) => {
    const { teamId, requestId } = event.params;
    const requestRef = db
      .collection('teams')
      .doc(teamId)
      .collection('deleteQueue')
      .doc(requestId);
    const payload = event.data?.data() || {};
    const type = (payload.type || '').toString();

    try {
      await markStatus(requestRef, 'running', {
        startedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      if (type === 'projectDelete') {
        const projectId = (payload.projectId || '').toString().trim();
        if (!projectId) {
          throw new Error('projectId is required for projectDelete');
        }
        await handleProjectDelete(teamId, projectId);
      } else if (type === 'teamDelete') {
        await handleTeamDelete(teamId);
      } else {
        throw new Error(`Unsupported delete queue type: ${type}`);
      }

      await markStatus(requestRef, 'done', {
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (error) {
      await markStatus(requestRef, 'failed', {
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
        errorMessage: error instanceof Error ? error.message : String(error),
      });
      throw error;
    }
  },
);
