const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const {
  arrayUnion,
  collectionGroup,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  where,
} = require('firebase/firestore');

const projectId = process.env.FIREBASE_RULES_PROJECT || 'demo-worshipflow';
const rulesPath = path.resolve(__dirname, '../../firestore.rules');

async function seed(testEnv) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const now = new Date().toISOString();

    await setDoc(doc(db, 'teams/team-alpha'), {
      name: 'Alpha Team',
      createdBy: 'owner-1',
      memberUids: ['owner-1', 'member-1', 'leader-1'],
      createdAt: now,
    });
    await setDoc(doc(db, 'teams/team-alpha/members/owner-1'), {
      userId: 'owner-1',
      uid: 'owner-1',
      email: 'owner-1@example.com',
      role: 'admin',
      teamName: 'Alpha Team',
      createdAt: now,
    });
    await setDoc(doc(db, 'teams/team-alpha/members/member-1'), {
      userId: 'member-1',
      uid: 'member-1',
      email: 'member-1@example.com',
      role: 'member',
      teamName: 'Alpha Team',
      createdAt: now,
    });
    await setDoc(doc(db, 'teams/team-alpha/members/leader-1'), {
      userId: 'leader-1',
      uid: 'leader-1',
      email: 'leader-1@example.com',
      role: 'leader',
      teamName: 'Alpha Team',
      createdAt: now,
    });
    await setDoc(doc(db, 'users/member-1/teamMemberships/team-alpha'), {
      teamId: 'team-alpha',
      teamName: 'Alpha Team',
      role: 'member',
      updatedAt: now,
    });
    await setDoc(doc(db, 'users/leader-1/teamMemberships/team-alpha'), {
      teamId: 'team-alpha',
      teamName: 'Alpha Team',
      role: 'leader',
      updatedAt: now,
    });
    await setDoc(doc(db, 'teams/team-alpha/projects/project-delete'), {
      date: '2026.03.18',
      title: '삭제 검증 프로젝트',
      leaderUserId: 'leader-1',
      createdAt: now,
    });
    await setDoc(doc(db, 'teams/team-alpha/projects/project-delete-denied'), {
      date: '2026.03.19',
      title: '삭제 거부 검증 프로젝트',
      leaderUserId: 'leader-1',
      createdAt: now,
    });
    await setDoc(doc(db, 'teams/team-alpha/invites/invited@example.com'), {
      email: 'invited@example.com',
      role: 'member',
      teamId: 'team-alpha',
      teamName: 'Alpha Team',
      status: 'pending',
      createdBy: 'owner-1',
      createdAt: now,
    });
    await setDoc(doc(db, 'teams/team-alpha/inviteLinks/link-alpha'), {
      teamId: 'team-alpha',
      teamName: 'Alpha Team',
      role: 'member',
      status: 'active',
      createdBy: 'owner-1',
      createdAt: now,
    });
    await setDoc(doc(db, 'teamNameIndex/alpha-team'), {
      teamId: 'team-alpha',
      teamName: 'Alpha Team',
      normalizedName: 'alpha-team',
      createdBy: 'owner-1',
      createdAt: now,
    });

    // Legacy-like edge case: memberUids missing, membership mirror only.
    await setDoc(doc(db, 'teams/team-beta'), {
      name: 'Beta Team',
      createdBy: 'owner-2',
      memberUids: [],
      createdAt: now,
    });
    await setDoc(doc(db, 'users/member-1/teamMemberships/team-beta'), {
      teamId: 'team-beta',
      teamName: 'Beta Team',
      role: 'member',
      updatedAt: now,
    });
  });
}

async function run() {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error(
      'FIRESTORE_EMULATOR_HOST is not set. Run via firebase emulators:exec.',
    );
  }
  const now = new Date().toISOString();

  const testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: fs.readFileSync(rulesPath, 'utf8'),
    },
  });

  try {
    await seed(testEnv);

    const outsiderDb = testEnv
      .authenticatedContext('outsider-1', { email: 'outsider@example.com' })
      .firestore();
    const memberDb = testEnv
      .authenticatedContext('member-1', { email: 'member-1@example.com' })
      .firestore();
    const ownerDb = testEnv
      .authenticatedContext('owner-1', { email: 'owner-1@example.com' })
      .firestore();
    const leaderDb = testEnv
      .authenticatedContext('leader-1', { email: 'leader-1@example.com' })
      .firestore();
    const owner2Db = testEnv
      .authenticatedContext('owner-2', { email: 'owner-2@example.com' })
      .firestore();
    const invitedDb = testEnv
      .authenticatedContext('invitee-1', { email: 'Invited@Example.com' })
      .firestore();
    const inviteLinkDb = testEnv
      .authenticatedContext('invitee-2', { email: 'Invitee2@Example.com' })
      .firestore();
    const requesterDb = testEnv
      .authenticatedContext('requester-1', { email: 'requester@example.com' })
      .firestore();

    // 1) Non-member should not read team.
    await assertFails(getDoc(doc(outsiderDb, 'teams/team-alpha')));

    // 2) Membership mirror should allow team read (self-healing compatibility).
    await assertSucceeds(getDoc(doc(memberDb, 'teams/team-beta')));

    // 3) Team creator should be able to recreate own member doc as admin.
    await assertSucceeds(
      setDoc(doc(owner2Db, 'teams/team-beta/members/owner-2'), {
        userId: 'owner-2',
        uid: 'owner-2',
        email: 'owner-2@example.com',
        role: 'admin',
        teamName: 'Beta Team',
      }),
    );

    // 4) Team admin can enqueue delete request.
    await assertSucceeds(
      setDoc(doc(ownerDb, 'teams/team-alpha/deleteQueue/req-team-delete'), {
        teamId: 'team-alpha',
        requestedBy: 'owner-1',
        type: 'teamDelete',
        status: 'queued',
      }),
    );

    // 5) Non-admin member cannot enqueue delete request.
    await assertFails(
      setDoc(doc(memberDb, 'teams/team-alpha/deleteQueue/req-denied'), {
        teamId: 'team-alpha',
        requestedBy: 'member-1',
        type: 'teamDelete',
        status: 'queued',
      }),
    );

    // 6) Team member can write ops metric; outsider cannot read it.
    await assertSucceeds(
      setDoc(doc(memberDb, 'teams/team-alpha/opsMetrics/metric-1'), {
        category: 'legacy_fallback',
        action: 'project_notes.legacy_query',
        status: 'used',
      }),
    );
    await assertFails(getDoc(doc(outsiderDb, 'teams/team-alpha/opsMetrics/metric-1')));
    await assertSucceeds(getDoc(doc(ownerDb, 'teams/team-alpha/opsMetrics/metric-1')));

    // 7) Only the project leader can delete the project doc.
    await assertFails(
      deleteDoc(doc(ownerDb, 'teams/team-alpha/projects/project-delete-denied')),
    );
    await assertSucceeds(
      deleteDoc(doc(leaderDb, 'teams/team-alpha/projects/project-delete')),
    );

    // 8) Duplicate-name flow can create a join request for a non-member
    // without relying on a direct team doc read.
    await assertFails(getDoc(doc(requesterDb, 'teams/team-alpha')));
    await assertSucceeds(getDoc(doc(requesterDb, 'teamNameIndex/alpha-team')));
    await assertSucceeds(
      setDoc(doc(requesterDb, 'teams/team-alpha/joinRequests/requester-1'), {
        requesterUid: 'requester-1',
        requesterEmail: 'requester@example.com',
        teamId: 'team-alpha',
        teamName: 'Alpha Team',
        status: 'pending',
      }),
    );
    await assertSucceeds(
      getDoc(doc(requesterDb, 'teams/team-alpha/joinRequests/requester-1')),
    );

    // 9) Invited user can read pending invite and accept it with membership mirrors.
    await assertSucceeds(
      getDoc(doc(invitedDb, 'teams/team-alpha/invites/invited@example.com')),
    );
    await assertSucceeds(
      getDocs(
        query(
          collectionGroup(invitedDb, 'invites'),
          where('email', '==', 'invited@example.com'),
        ),
      ),
    );
    await assertSucceeds(
      getDocs(
        query(
          collectionGroup(memberDb, 'invites'),
          where('email', '==', 'member-1@example.com'),
        ),
      ),
    );
    await assertSucceeds(
      setDoc(doc(invitedDb, 'teams/team-alpha/members/invitee-1'), {
        userId: 'invitee-1',
        uid: 'invitee-1',
        email: 'invited@example.com',
        role: 'member',
        teamName: 'Alpha Team',
        createdAt: now,
      }),
    );
    await assertSucceeds(
      setDoc(doc(invitedDb, 'users/invitee-1/teamMemberships/team-alpha'), {
        teamId: 'team-alpha',
        teamName: 'Alpha Team',
        role: 'member',
        updatedAt: now,
      }),
    );
    await assertSucceeds(
      setDoc(
        doc(invitedDb, 'teams/team-alpha'),
        {
          memberUids: arrayUnion('invitee-1'),
        },
        { merge: true },
      ),
    );
    await assertSucceeds(
      setDoc(
        doc(invitedDb, 'teams/team-alpha/invites/invited@example.com'),
        {
          status: 'accepted',
          acceptedBy: 'invitee-1',
          acceptedAt: now,
        },
        { merge: true },
      ),
    );

    // 10) Active invite link can be consumed to create both membership mirrors.
    await assertSucceeds(
      getDoc(doc(inviteLinkDb, 'teams/team-alpha/inviteLinks/link-alpha')),
    );
    await assertSucceeds(
      setDoc(doc(inviteLinkDb, 'teams/team-alpha/members/invitee-2'), {
        userId: 'invitee-2',
        uid: 'invitee-2',
        email: 'invitee2@example.com',
        role: 'member',
        teamName: 'Alpha Team',
        inviteLinkId: 'link-alpha',
        createdAt: now,
      }),
    );
    await assertSucceeds(
      setDoc(doc(inviteLinkDb, 'users/invitee-2/teamMemberships/team-alpha'), {
        teamId: 'team-alpha',
        teamName: 'Alpha Team',
        role: 'member',
        updatedAt: now,
      }),
    );
    await assertSucceeds(
      setDoc(
        doc(inviteLinkDb, 'teams/team-alpha'),
        {
          memberUids: arrayUnion('invitee-2'),
        },
        { merge: true },
      ),
    );

    console.log('Firestore rules self-healing suite passed.');
  } finally {
    await testEnv.cleanup();
  }
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
