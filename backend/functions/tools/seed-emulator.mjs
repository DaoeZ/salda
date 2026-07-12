// Siembra una sesión de prueba en el emulador para el E2E manual de la web.
process.env.FIRESTORE_EMULATOR_HOST = 'localhost:8080';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

initializeApp({ projectId: 'demo-salda' });
const db = getFirestore();

const S = 'sessions/e2e1';
await db.doc(S).set({
  schemaVersion: 1,
  ownerUid: 'owner-e2e',
  kind: 'single',
  name: 'Cena Casa Paco',
  currency: 'EUR',
  status: 'open',
  splitModeDefault: 'byItem',
  shareCode: 'E2E-SECRET-CODE-16CH',
  ownerParticipantId: 'p0',
  computeVersion: 1,
  totals: { grandTotal: 5190, settledConfirmed: 890, settledMarked: 0 },
  balances: {
    p0: { paid: 5190, consumed: 1730, net: 3460, outstanding: 2570 },
    p1: { paid: 0, consumed: 1730, net: -1730, outstanding: -1730 },
    p2: { paid: 0, consumed: 1730, net: -1730, outstanding: -840 },
  },
  paymentMethodsSnapshot: {
    bizumPhone: '612345678',
    paypalLink: 'paypal.me/edgarpaco',
    iban: 'ES9121000418450200051332',
  },
  participantsCount: 3,
  pendingSettlements: 2,
  updatedAt: new Date(),
});
const participants = [
  ['p0', 'Edgar', true, ''],
  ['p1', 'Alba', false, ''],
  ['p2', 'Lucía', false, ''],
];
for (const [id, name, isOwner, claimed] of participants) {
  await db.doc(`${S}/participants/${id}`).set({
    name, isOwner, order: Number(id[1]), claimedByDevice: claimed, active: true,
  });
}
await db.doc(`${S}/accounts/a0`).set({ name: 'Casa Paco', order: 0 });
await db.doc(`${S}/accounts/a0/tickets/t0`).set({
  kind: 'scanned',
  merchant: { name: 'Casa Paco' },
  grandTotal: 5190,
  paidByParticipantId: 'p0',
});
const lines = [
  ['l0', 'Cerveza caña ×3', 750],
  ['l1', 'Ensalada mixta', 890],
  ['l2', 'Solomillo ibérico ×2', 3100],
  ['l3', 'Pan y aperitivo', 450],
];
for (const [id, name, total] of lines) {
  await db.doc(`${S}/accounts/a0/tickets/t0/lines/${id}`).set({
    name, quantityMilli: 1000, totalPrice: total, order: Number(id[1]),
    assignment: { type: 'unassigned', participants: {} },
  });
}
await db.doc(`${S}/settlements/st1`).set({
  from: 'p1', to: 'p0', amount: 1730, state: 'pending', stateHistory: [],
});
await db.doc(`${S}/settlements/st2`).set({
  from: 'p2', to: 'p0', amount: 840, state: 'pending', stateHistory: [],
});
console.log('SEEDED http://localhost:5173/s/e2e1#k=E2E-SECRET-CODE-16CH');
