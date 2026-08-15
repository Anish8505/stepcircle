import { createHash, randomBytes } from 'node:crypto';

import { initializeApp } from 'firebase-admin/app';
import { FieldValue, getFirestore, Timestamp } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { setGlobalOptions } from 'firebase-functions/v2';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';

initializeApp();
setGlobalOptions({
  region: 'asia-south1',
  maxInstances: 2,
  concurrency: 10,
  memory: '256MiB',
  timeoutSeconds: 30,
  // A full CPU is required when requests can be handled concurrently.
  // The two-instance cap remains the primary cost safeguard.
  cpu: 1,
});

const db = getFirestore();
const maxDailySteps = 100000;

type Profile = {
  displayName?: string;
  photoUrl?: string;
  city?: string;
  countryCode?: string;
  showCityOnGlobalLeaderboard?: boolean;
  timeZoneOffsetMinutes?: number;
};
type StepRecord = {
  userId?: string;
  dateKey?: string;
  steps?: number;
  updatedAt?: Timestamp;
  globalOptInAtSync?: boolean;
};

function requireUserId(auth: { uid: string } | undefined): string {
  if (auth == null) throw new HttpsError('unauthenticated', 'Sign in is required.');
  return auth.uid;
}

function readString(value: unknown, name: string): string {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new HttpsError('invalid-argument', `${name} is required.`);
  }
  return value.trim();
}

function friendshipId(firstUserId: string, secondUserId: string): string {
  return [firstUserId, secondUserId].sort().join('_');
}

function isTodayOrAdjacentUtc(dateKey: string): boolean {
  if (!/^\d{8}$/.test(dateKey)) return false;
  const requested = Date.UTC(
    Number(dateKey.slice(0, 4)),
    Number(dateKey.slice(4, 6)) - 1,
    Number(dateKey.slice(6, 8)),
  );
  const today = new Date();
  const current = Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate());
  return Math.abs(requested - current) <= 24 * 60 * 60 * 1000;
}

function dateKeyForNow(): string {
  const now = new Date();
  return `${now.getUTCFullYear()}${String(now.getUTCMonth() + 1).padStart(2, '0')}${String(now.getUTCDate()).padStart(2, '0')}`;
}

function dateKeyForOffset(time: number, offsetMinutes: number): string {
  const local = new Date(time + offsetMinutes * 60 * 1000);
  return `${local.getUTCFullYear()}${String(local.getUTCMonth() + 1).padStart(2, '0')}${String(local.getUTCDate()).padStart(2, '0')}`;
}

function rankLabel(rank: number): string {
  if (rank === 1) return 'winner';
  if (rank === 2) return 'second';
  if (rank === 3) return 'third';
  return `rank_${rank}`;
}

async function directFriendIds(userId: string): Promise<string[]> {
  const snapshot = await db.collection('userFriends').doc(userId).collection('friends').get();
  return snapshot.docs.map((document) => document.id);
}

async function rankInViewerLeaderboard(viewerId: string, participantId: string, dateKey: string): Promise<number | null> {
  const entry = await db.collection('friendLeaderboards').doc(`${viewerId}_${dateKey}`)
    .collection('entries').doc(participantId).get();
  return entry.exists ? Number(entry.data()?.rank ?? 0) : null;
}

async function notifyFriendOvertaken(friendId: string, displayName: string): Promise<void> {
  const tokens = await db.collection('userNotificationTokens').doc(friendId).collection('tokens').get();
  const values = tokens.docs.map((document) => document.data().token).filter((token): token is string => typeof token === 'string');
  if (values.length === 0) return;
  const result = await getMessaging().sendEachForMulticast({
    tokens: values,
    notification: {
      title: 'StepCircle update',
      body: '$displayName has moved ahead of you today. Time for a walk?',
    },
    data: { type: 'friend_overtake' },
  });
  const removals = result.responses.flatMap((response, index) =>
    response.success ? [] : [tokens.docs[index].ref],
  );
  if (removals.length > 0) await Promise.all(removals.map((reference) => reference.delete()));
}

async function rebuildViewerLeaderboard(viewerId: string, dateKey: string): Promise<void> {
  const [viewerProfileSnapshot, friendIds] = await Promise.all([
    db.collection('users').doc(viewerId).get(),
    directFriendIds(viewerId),
  ]);
  const participantIds = [viewerId, ...friendIds];
  const participants = await Promise.all(
    participantIds.map(async (participantId) => {
      const [profileSnapshot, stepSnapshot] = await Promise.all([
        db.collection('users').doc(participantId).get(),
        db.collection('dailySteps').doc(`${participantId}_${dateKey}`).get(),
      ]);
      const stepRecord = (stepSnapshot.data() ?? {}) as StepRecord;
      return {
        participantId,
        profile: (profileSnapshot.data() ?? {}) as Profile,
        steps: stepRecord.steps ?? 0,
        updatedAt: stepRecord.updatedAt ?? Timestamp.fromMillis(0),
      };
    }),
  );
  participants.sort(
    (left, right) =>
      right.steps - left.steps ||
      left.updatedAt.toMillis() - right.updatedAt.toMillis() ||
      left.participantId.localeCompare(right.participantId),
  );

  const leaderboard = db.collection('friendLeaderboards').doc(`${viewerId}_${dateKey}`);
  const entries = leaderboard.collection('entries');
  const existing = await entries.get();
  const batch = db.batch();
  const allowed = new Set(participantIds);
  for (const document of existing.docs) {
    if (!allowed.has(document.id)) batch.delete(document.ref);
  }
  participants.forEach((participant, index) => {
    batch.set(entries.doc(participant.participantId), {
      participantUserId: participant.participantId,
      displayName: participant.profile.displayName ?? 'StepCircle user',
      photoUrl: participant.profile.photoUrl ?? null,
      steps: participant.steps,
      rank: index + 1,
      updatedAt: participant.updatedAt,
    });
  });
  batch.set(leaderboard, {
    viewerUserId: viewerId,
    dateKey,
    viewerTimeZoneOffsetMinutes: viewerProfileSnapshot.data()?.timeZoneOffsetMinutes ?? 330,
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  await batch.commit();
}

async function rebuildGlobalLeaderboard(dateKey: string): Promise<void> {
  const stepSnapshots = await db.collection('dailySteps')
    .where('dateKey', '==', dateKey)
    .where('globalOptInAtSync', '==', true)
    .get();

  const participants = await Promise.all(stepSnapshots.docs.map(async (document) => {
    const stepRecord = document.data() as StepRecord;
    const userId = stepRecord.userId ?? document.id.split('_')[0];
    const profileSnapshot = await db.collection('users').doc(userId).get();
    const profile = (profileSnapshot.data() ?? {}) as Profile;
    const canShowLocation = profile.showCityOnGlobalLeaderboard === true;
    return {
      userId,
      displayName: profile.displayName ?? 'StepCircle user',
      photoUrl: profile.photoUrl ?? null,
      steps: stepRecord.steps ?? 0,
      updatedAt: stepRecord.updatedAt ?? Timestamp.fromMillis(0),
      city: canShowLocation ? profile.city ?? null : null,
      countryCode: canShowLocation ? profile.countryCode ?? null : null,
    };
  }));

  participants.sort(
    (left, right) =>
      right.steps - left.steps ||
      left.updatedAt.toMillis() - right.updatedAt.toMillis() ||
      left.userId.localeCompare(right.userId),
  );

  const leaderboard = db.collection('globalLeaderboard').doc(dateKey);
  const entries = leaderboard.collection('entries');
  const existing = await entries.get();
  const participantIds = new Set(participants.map((participant) => participant.userId));
  const batch = db.batch();
  for (const document of existing.docs) {
    if (!participantIds.has(document.id)) batch.delete(document.ref);
  }
  participants.forEach((participant, index) => {
    batch.set(entries.doc(participant.userId), {
      userId: participant.userId,
      displayName: participant.displayName,
      photoUrl: participant.photoUrl,
      steps: participant.steps,
      rank: index + 1,
      city: participant.city,
      countryCode: participant.countryCode,
      updatedAt: participant.updatedAt,
    });
  });
  batch.set(leaderboard, {
    dateKey,
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  await batch.commit();
}

export const syncDailySteps = onCall(async (request) => {
  const userId = requireUserId(request.auth);
  const dateKey = readString(request.data?.dateKey, 'dateKey');
  const steps = request.data?.steps;
  // Older installed app builds did not send this value. Defaulting them to
  // India keeps those users syncing until they install the current release.
  const timeZoneOffsetMinutes = Number.isInteger(request.data?.timeZoneOffsetMinutes)
    ? request.data.timeZoneOffsetMinutes
    : 330;
  if (!isTodayOrAdjacentUtc(dateKey)) {
    throw new HttpsError('invalid-argument', 'Only the current local day may be synced.');
  }
  if (!Number.isInteger(steps) || steps < 0 || steps > maxDailySteps) {
    throw new HttpsError('invalid-argument', 'Steps must be a valid daily total.');
  }
  if (timeZoneOffsetMinutes < -720 || timeZoneOffsetMinutes > 840) {
    throw new HttpsError('invalid-argument', 'A valid local time zone offset is required.');
  }
  const now = Timestamp.now();
  const profileReference = db.collection('users').doc(userId);
  const profile = await profileReference.get();
  await profileReference.set({ timeZoneOffsetMinutes }, { merge: true });
  await db.collection('dailySteps').doc(`${userId}_${dateKey}`).set({
    userId,
    dateKey,
    steps,
    updatedAt: now,
    globalOptInAtSync: profile.data()?.globalLeaderboardOptIn === true,
  });
  const viewers = [userId, ...(await directFriendIds(userId))];
  const previousRanks = new Map<string, { user: number | null; friend: number | null }>();
  await Promise.all(viewers.slice(1).map(async (friendId) => {
    const [userRank, friendRank] = await Promise.all([
      rankInViewerLeaderboard(friendId, userId, dateKey),
      rankInViewerLeaderboard(friendId, friendId, dateKey),
    ]);
    previousRanks.set(friendId, { user: userRank, friend: friendRank });
  }));
  await Promise.all(viewers.map((viewerId) => rebuildViewerLeaderboard(viewerId, dateKey)));
  const displayName = profile.data()?.displayName ?? 'A friend';
  await Promise.all(viewers.slice(1).map(async (friendId) => {
    const previous = previousRanks.get(friendId);
    if (previous?.user == null || previous.friend == null) return;
    const [userRank, friendRank] = await Promise.all([
      rankInViewerLeaderboard(friendId, userId, dateKey),
      rankInViewerLeaderboard(friendId, friendId, dateKey),
    ]);
    if (userRank != null && friendRank != null && previous.user > previous.friend && userRank < friendRank) {
      await notifyFriendOvertaken(friendId, displayName);
    }
  }));
  await rebuildGlobalLeaderboard(dateKey);
  return { syncedAt: now.toDate().toISOString() };
});

export const registerNotificationToken = onCall(async (request) => {
  const userId = requireUserId(request.auth);
  const token = readString(request.data?.token, 'token');
  if (token.length < 20 || token.length > 512) {
    throw new HttpsError('invalid-argument', 'The notification token is invalid.');
  }
  const tokenId = createHash('sha256').update(token).digest('hex');
  await db.collection('userNotificationTokens').doc(userId).collection('tokens').doc(tokenId).set({
    token,
    updatedAt: FieldValue.serverTimestamp(),
  });
  return { registered: true };
});

/// Runs hourly so every member's local previous day is saved shortly after
/// midnight. Snapshots are written once and never recalculated after that.
export const finalizeDailyRankSnapshots = onSchedule(
  { schedule: 'every 60 minutes', timeZone: 'Etc/UTC' },
  async () => {
    const now = Date.now();
    const candidateDateKeys = [
      dateKeyForOffset(now - 24 * 60 * 60 * 1000, 0),
      dateKeyForOffset(now, 0),
    ];
    for (const dateKey of candidateDateKeys) {
      const leaderboards = await db.collection('friendLeaderboards')
        .where('dateKey', '==', dateKey)
        .get();
      for (const leaderboard of leaderboards.docs) {
        const data = leaderboard.data();
        const offset = Number(data.viewerTimeZoneOffsetMinutes ?? 330);
        const priorLocalDay = dateKeyForOffset(now - 24 * 60 * 60 * 1000, offset);
        if (data.dateKey !== priorLocalDay) continue;

        const snapshotReference = db.collection('viewerFriendRankSnapshots')
          .doc(`${data.viewerUserId}_${data.dateKey}`);
        if ((await snapshotReference.get()).exists) continue;
        const entries = await leaderboard.ref.collection('entries').orderBy('rank').get();
        const calculatedAt = Timestamp.now();
        const batch = db.batch();
        const totalParticipants = entries.size;
        batch.create(snapshotReference, {
          viewerUserId: data.viewerUserId,
          dateKey: data.dateKey,
          totalParticipants,
          calculatedAt,
        });
        for (const entry of entries.docs) {
          const participant = entry.data();
          const rank = Number(participant.rank ?? 0);
          batch.create(snapshotReference.collection('entries').doc(entry.id), {
            participantUserId: participant.participantUserId,
            dateKey: data.dateKey,
            steps: participant.steps ?? 0,
            rank,
            totalParticipants,
            rankLabel: rankLabel(rank),
            calculatedAt,
          });
        }
        await batch.commit();
      }
    }
  },
);

export const createFriendInvite = onCall(async (request) => {
  const invitedByUserId = requireUserId(request.auth);
  const invitationCode = randomBytes(18).toString('base64url');
  const expiresAt = Timestamp.fromMillis(Date.now() + 7 * 24 * 60 * 60 * 1000);
  await db.collection('friendInvites').doc(invitationCode).create({
    invitedByUserId,
    invitationCode,
    status: 'pending',
    expiresAt,
    createdAt: FieldValue.serverTimestamp(),
  });
  return { invitationCode, expiresAt: expiresAt.toDate().toISOString() };
});

export const acceptFriendInvite = onCall(async (request) => {
  const acceptingUserId = requireUserId(request.auth);
  const invitationCode = readString(request.data?.invitationCode, 'invitationCode');
  const inviteReference = db.collection('friendInvites').doc(invitationCode);
  let invitedByUserId = '';
  await db.runTransaction(async (transaction) => {
    const invite = await transaction.get(inviteReference);
    if (!invite.exists || invite.data()?.status !== 'pending') {
      throw new HttpsError('not-found', 'This invitation is no longer available.');
    }
    invitedByUserId = invite.data()?.invitedByUserId as string;
    if (invitedByUserId === acceptingUserId) {
      throw new HttpsError('invalid-argument', 'You cannot accept your own invitation.');
    }
    if ((invite.data()?.expiresAt as Timestamp).toMillis() < Date.now()) {
      throw new HttpsError('deadline-exceeded', 'This invitation has expired.');
    }
    const id = friendshipId(invitedByUserId, acceptingUserId);
    transaction.set(db.collection('friendships').doc(id), {
      userAId: [invitedByUserId, acceptingUserId].sort()[0],
      userBId: [invitedByUserId, acceptingUserId].sort()[1],
      status: 'accepted',
      invitedByUserId,
      invitationCode,
      acceptedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      createdAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    transaction.set(db.collection('userFriends').doc(invitedByUserId).collection('friends').doc(acceptingUserId), {
      friendId: acceptingUserId,
      friendshipId: id,
      addedAt: FieldValue.serverTimestamp(),
    });
    transaction.set(db.collection('userFriends').doc(acceptingUserId).collection('friends').doc(invitedByUserId), {
      friendId: invitedByUserId,
      friendshipId: id,
      addedAt: FieldValue.serverTimestamp(),
    });
    transaction.update(inviteReference, { status: 'accepted', acceptedAt: FieldValue.serverTimestamp() });
  });
  const dateKey = typeof request.data?.dateKey === 'string' && isTodayOrAdjacentUtc(request.data.dateKey)
    ? request.data.dateKey
    : dateKeyForNow();
  await Promise.all([
    rebuildViewerLeaderboard(acceptingUserId, dateKey),
    rebuildViewerLeaderboard(invitedByUserId, dateKey),
  ]);
  return { accepted: true };
});

/// Lets a signed-in member rebuild only their own private direct-friends board.
/// It is used when an invitation completes near a local-day boundary.
export const refreshFriendsLeaderboard = onCall(async (request) => {
  const userId = requireUserId(request.auth);
  const requestedDateKey = request.data?.dateKey;
  const dateKey = typeof requestedDateKey === 'string' && isTodayOrAdjacentUtc(requestedDateKey)
    ? requestedDateKey
    : dateKeyForNow();
  const viewers = [userId, ...(await directFriendIds(userId))];
  await Promise.all(viewers.map((viewerId) => rebuildViewerLeaderboard(viewerId, dateKey)));
  return { refreshed: true };
});

export const declineFriendInvite = onCall(async (request) => {
  const userId = requireUserId(request.auth);
  const invitationCode = readString(request.data?.invitationCode, 'invitationCode');
  const reference = db.collection('friendInvites').doc(invitationCode);
  const invite = await reference.get();
  if (!invite.exists || invite.data()?.status !== 'pending' || invite.data()?.invitedByUserId === userId) {
    throw new HttpsError('not-found', 'This invitation is no longer available.');
  }
  await reference.update({ status: 'declined', declinedByUserId: userId, updatedAt: FieldValue.serverTimestamp() });
  return { declined: true };
});

export const removeFriend = onCall(async (request) => {
  const userId = requireUserId(request.auth);
  const friendId = readString(request.data?.friendId, 'friendId');
  const id = friendshipId(userId, friendId);
  const friendshipReference = db.collection('friendships').doc(id);
  const friendship = await friendshipReference.get();
  if (!friendship.exists || friendship.data()?.status !== 'accepted') {
    throw new HttpsError('not-found', 'This direct friendship does not exist.');
  }
  const batch = db.batch();
  batch.update(friendshipReference, { status: 'revoked', updatedAt: FieldValue.serverTimestamp() });
  batch.delete(db.collection('userFriends').doc(userId).collection('friends').doc(friendId));
  batch.delete(db.collection('userFriends').doc(friendId).collection('friends').doc(userId));
  await batch.commit();
  const dateKey = dateKeyForNow();
  await Promise.all([rebuildViewerLeaderboard(userId, dateKey), rebuildViewerLeaderboard(friendId, dateKey)]);
  return { removed: true };
});

export const updatePublicLocation = onCall(async (request) => {
  const userId = requireUserId(request.auth);
  const city = readString(request.data?.city, 'city').slice(0, 80);
  await db.collection('users').doc(userId).set({
    publicCity: city,
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  return { city };
});
