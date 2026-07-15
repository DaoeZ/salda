/**
 * Estado vivo de la sesión para el invitado (runas de Svelte 5).
 *
 * Lecturas: sesión, participantes y liquidaciones en tiempo real; tickets y
 * líneas bajo demanda (las líneas en vivo: se ve a los demás elegir).
 * Escrituras: EXACTAMENTE las tres que permiten las reglas (spec §13.2):
 * reclamar/liberar nombre, autoasignarse líneas y marcar su pago.
 * Aquí no se calcula dinero jamás: los importes vienen de la function.
 */
import {
  arrayUnion,
  collection,
  doc,
  getDoc,
  getDocs,
  onSnapshot,
  orderBy,
  query,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
} from 'firebase/firestore';

import { isPickedBy, toggleSelf, type Assignment } from './assignment';
import { db, ensureSignedIn } from './firebase';
import {
  forgetParticipant,
  rememberParticipant,
  rememberedParticipant,
} from './identity';
import type { ShareLink } from './link';

export type Phase = 'connecting' | 'invalid' | 'ready';

export interface SessionInfo {
  name: string;
  status: 'open' | 'closed' | 'archived';
  splitModeDefault: 'equal' | 'byItem';
  totals: {
    grandTotal: number;
    settlementRequired: number;
    settledConfirmed: number;
    settledMarked: number;
  };
  balances: Record<
    string,
    { paid: number; consumed: number; net: number; outstanding: number }
  >;
  paymentMethods: {
    bizumPhone?: string;
    paypalLink?: string;
    revolutTag?: string;
    iban?: string;
  };
}

export interface Participant {
  id: string;
  name: string;
  isOwner: boolean;
  claimedByDevice: string;
}

export interface SettlementInfo {
  id: string;
  from: string;
  to: string;
  amount: number;
  state: 'pending' | 'marked' | 'confirmed';
}

export interface LineInfo {
  id: string;
  path: string;
  name: string;
  quantityMilli: number;
  totalPrice: number;
  assignment: Assignment | undefined;
}

export interface TicketInfo {
  id: string;
  merchantName: string;
  grandTotal: number;
  pickable: boolean; // modo efectivo byItem
  lines: LineInfo[];
}

class GuestSession {
  phase = $state<Phase>('connecting');
  session = $state<SessionInfo | null>(null);
  participants = $state<Participant[]>([]);
  settlements = $state<SettlementInfo[]>([]);
  tickets = $state<TicketInfo[]>([]);
  ticketsLoaded = $state(false);
  myPid = $state<string | null>(null);

  private uid = '';
  private sid = '';
  private stopTickets: Array<() => void> = [];

  get me(): Participant | null {
    return this.participants.find((p) => p.id === this.myPid) ?? null;
  }

  get open(): boolean {
    return this.session?.status === 'open';
  }

  async connect(link: ShareLink): Promise<void> {
    this.sid = link.sessionId;
    try {
      const user = await ensureSignedIn();
      this.uid = user.uid;

      // Prueba de conocimiento del shareCode (una vez por dispositivo).
      const accessRef = doc(db, 'sessions', this.sid, 'guestAccess', this.uid);
      if (!(await getDoc(accessRef)).exists()) {
        await setDoc(accessRef, { shareCode: link.shareCode });
      }

      onSnapshot(
        doc(db, 'sessions', this.sid),
        (snap) => {
          const data = snap.data();
          if (!data) {
            this.phase = 'invalid';
            return;
          }
          this.session = {
            name: (data.name as string) ?? '',
            status: (data.status as SessionInfo['status']) ?? 'open',
            splitModeDefault:
              (data.splitModeDefault as 'equal' | 'byItem') ?? 'equal',
            totals: {
              grandTotal: (data.totals?.grandTotal as number) ?? 0,
              settlementRequired:
                (data.totals?.settlementRequired as number) ??
                (data.totals?.settledConfirmed as number) ??
                0,
              settledConfirmed:
                (data.totals?.settledConfirmed as number) ?? 0,
              settledMarked: (data.totals?.settledMarked as number) ?? 0,
            },
            balances:
              (data.balances as SessionInfo['balances']) ?? {},
            paymentMethods:
              (data.paymentMethodsSnapshot as SessionInfo['paymentMethods']) ??
              {},
          };
          this.phase = 'ready';
        },
        () => (this.phase = 'invalid'),
      );

      onSnapshot(
        query(
          collection(db, 'sessions', this.sid, 'participants'),
          orderBy('order'),
        ),
        (snap) => {
          this.participants = snap.docs.map((d) => ({
            id: d.id,
            name: (d.data().name as string) ?? '',
            isOwner: (d.data().isOwner as boolean) ?? false,
            claimedByDevice: (d.data().claimedByDevice as string) ?? '',
          }));
          this.syncIdentity();
        },
      );

      onSnapshot(
        collection(db, 'sessions', this.sid, 'settlements'),
        (snap) => {
          this.settlements = snap.docs
            .map((d) => ({
              id: d.id,
              from: (d.data().from as string) ?? '',
              to: (d.data().to as string) ?? '',
              amount: (d.data().amount as number) ?? 0,
              state:
                (d.data().state as SettlementInfo['state']) ?? 'pending',
            }))
            .sort((a, b) => b.amount - a.amount);
        },
      );
    } catch {
      // Código incorrecto, sesión cerrada para nuevos invitados o red.
      this.phase = 'invalid';
    }
  }

  /** Restaura la identidad recordada y detecta si el owner liberó el nombre. */
  private syncIdentity(): void {
    const remembered = rememberedParticipant(this.sid);
    if (!remembered) return;
    const participant = this.participants.find((p) => p.id === remembered);
    if (participant && participant.claimedByDevice === this.uid) {
      this.myPid = remembered;
    } else if (this.myPid) {
      this.myPid = null;
      forgetParticipant(this.sid);
    }
  }

  /** "Selecciona quién eres": reclama un nombre libre (o re-reclama el suyo). */
  async claim(pid: string): Promise<'ok' | 'taken'> {
    try {
      await updateDoc(
        doc(db, 'sessions', this.sid, 'participants', pid),
        { claimedByDevice: this.uid },
      );
      this.myPid = pid;
      rememberParticipant(this.sid, pid);
      return 'ok';
    } catch {
      return 'taken'; // reclamado por otro dispositivo (regla lo impide)
    }
  }

  async release(): Promise<void> {
    if (!this.myPid) return;
    await updateDoc(
      doc(db, 'sessions', this.sid, 'participants', this.myPid),
      { claimedByDevice: '' },
    );
    this.myPid = null;
    forgetParticipant(this.sid);
  }

  /** "Ya he pagado": pending → marked SOLO en las suyas (regla). */
  async markPaid(settlementId: string): Promise<void> {
    await updateDoc(
      doc(db, 'sessions', this.sid, 'settlements', settlementId),
      {
        state: 'marked',
        stateHistory: arrayUnion({
          state: 'marked',
          at: Timestamp.now(),
          by: 'guest',
        }),
        updatedAt: serverTimestamp(),
      },
    );
  }

  /** Marca/desmarca un producto como suyo (modo byItem, sesión abierta). */
  async toggleLine(line: LineInfo): Promise<void> {
    if (!this.myPid) return;
    await updateDoc(doc(db, line.path), {
      assignment: toggleSelf(line.assignment, this.myPid),
    });
  }

  isMine(line: LineInfo): boolean {
    return this.myPid != null && isPickedBy(line.assignment, this.myPid);
  }

  /** Carga tickets y suscribe sus líneas en vivo (se ve elegir a los demás). */
  async loadTickets(): Promise<void> {
    if (this.ticketsLoaded) return;
    this.ticketsLoaded = true;
    for (const stop of this.stopTickets) stop();
    this.stopTickets = [];

    const accounts = await getDocs(
      query(collection(db, 'sessions', this.sid, 'accounts'), orderBy('order')),
    );
    const found: TicketInfo[] = [];
    for (const account of accounts.docs) {
      const tickets = await getDocs(collection(account.ref, 'tickets'));
      for (const ticket of tickets.docs) {
        const info: TicketInfo = {
          id: ticket.id,
          merchantName:
            (ticket.data().merchant?.name as string) ??
            (account.data().name as string) ??
            '',
          grandTotal: (ticket.data().grandTotal as number) ?? 0,
          pickable:
            ((ticket.data().splitModeOverride as string) ??
              this.session?.splitModeDefault) === 'byItem',
          lines: [],
        };
        found.push(info);
        const stop = onSnapshot(
          query(collection(ticket.ref, 'lines'), orderBy('order')),
          (snap) => {
            info.lines = snap.docs.map((d) => ({
              id: d.id,
              path: d.ref.path,
              name: (d.data().name as string) ?? '',
              quantityMilli: (d.data().quantityMilli as number) ?? 1000,
              totalPrice: (d.data().totalPrice as number) ?? 0,
              assignment: d.data().assignment as Assignment | undefined,
            }));
            this.tickets = [...found]; // notificar a las runas
          },
        );
        this.stopTickets.push(stop);
      }
    }
    this.tickets = found;
  }
}

export const guest = new GuestSession();
