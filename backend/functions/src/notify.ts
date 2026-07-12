/**
 * notify — avisos FCM al anfitrión (spec §12.2, RF-95).
 *
 * pending→marked: "X ha marcado que ha pagado".
 * Última liquidación confirmada: "Todos han pagado".
 * Sin tokens registrados no hay envío (la app los guarda en users/{uid}).
 */
import { getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { logger } from 'firebase-functions/v2';
import { onDocumentUpdated } from 'firebase-functions/v2/firestore';

export const notifyOnSettlement = onDocumentUpdated(
  'sessions/{sid}/settlements/{stid}',
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after || before.state === after.state) return;

    const db = getFirestore();
    const sessionRef = db.doc(`sessions/${event.params.sid}`);
    const session = (await sessionRef.get()).data();
    if (!session) return;

    const tokens = await ownerTokens(session.ownerUid as string);
    if (tokens.length === 0) return;

    const euros = (cents: number) =>
      `${(cents / 100).toFixed(2).replace('.', ',')} €`;

    if (before.state === 'pending' && after.state === 'marked') {
      const from = await sessionRef
        .collection('participants')
        .doc(after.from as string)
        .get();
      await send(tokens, {
        title: session.name as string,
        body: `${from.data()?.name ?? 'Alguien'} ha marcado que ha pagado ` +
          `${euros(after.amount as number)}`,
      });
    }

    if (after.state === 'confirmed') {
      const all = await sessionRef.collection('settlements').get();
      const allConfirmed = all.docs.every(
        (d) => d.data().state === 'confirmed',
      );
      if (allConfirmed && all.size > 0) {
        await send(tokens, {
          title: session.name as string,
          body: 'Todos han pagado. Cuenta saldada 🎉',
        });
      }
    }
  },
);

async function ownerTokens(ownerUid: string): Promise<string[]> {
  const user = await getFirestore().doc(`users/${ownerUid}`).get();
  return ((user.data()?.fcmTokens as string[] | undefined) ?? []).filter(
    (t) => typeof t === 'string' && t.length > 0,
  );
}

async function send(
  tokens: string[],
  notification: { title: string; body: string },
): Promise<void> {
  const response = await getMessaging().sendEachForMulticast({
    tokens,
    notification,
  });
  if (response.failureCount > 0) {
    logger.warn('FCM con fallos', { failures: response.failureCount });
  }
}
