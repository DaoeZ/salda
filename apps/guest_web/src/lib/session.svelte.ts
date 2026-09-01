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
  deleteField,
  doc,
  getDoc,
  onSnapshot,
  orderBy,
  query,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
} from 'firebase/firestore';

import {
  isPickedBy,
  setUnits,
  toggleSelf,
  unitIsPickedBy,
  unitUpdate,
  usesUnitModel,
  type Assignment,
} from './assignment';
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
  accountId: string;
  merchantName: string;
  grandTotal: number;
  pickable: boolean; // modo efectivo byItem
  /** Lo que declara el ticket; `undefined` = hereda el de la sesión. */
  splitModeOverride: string | undefined;
  lines: LineInfo[];
}

/**
 * Ficha de un ticket, sin Firestore de por medio (A6).
 *
 * Se extrae para poder probarla: el modo efectivo lo decide el ticket y, si
 * no lo declara, la sesión. Antes esto se calculaba una sola vez al cargar,
 * así que un cambio de modo dejaba la pestaña de productos mintiendo.
 */
export function ticketInfoFrom(
  id: string,
  accountId: string,
  data: Record<string, unknown>,
  accountName: string,
  sessionMode: 'equal' | 'byItem' | undefined,
): Omit<TicketInfo, 'lines'> {
  const merchant = data.merchant as { name?: string } | undefined;
  const splitModeOverride = data.splitModeOverride as string | undefined;
  return {
    id,
    accountId,
    merchantName: merchant?.name ?? accountName ?? '',
    grandTotal: (data.grandTotal as number) ?? 0,
    splitModeOverride,
    pickable: (splitModeOverride ?? sessionMode) === 'byItem',
  };
}

/**
 * Traduce el fallo de una escritura a algo que una persona entienda (A5).
 *
 * Antes, una escritura rechazada era una promesa sin capturar: la casilla
 * revertía sola y nadie explicaba por qué. Con el reparto por unidades hay
 * motivos legítimos y frecuentes para que Rules digan que no.
 */
export function describeWriteError(error: unknown): string {
  const code = (error as { code?: string } | null)?.code ?? '';
  if (code === 'permission-denied') {
    return 'No se pudo guardar. Puede que la cuenta ya esté cerrada o que ' +
      'alguien haya cambiado el reparto; recarga la página.';
  }
  return 'No se pudo guardar. Revisa tu conexión e inténtalo otra vez.';
}

class GuestSession {
  phase = $state<Phase>('connecting');
  session = $state<SessionInfo | null>(null);
  participants = $state<Participant[]>([]);
  settlements = $state<SettlementInfo[]>([]);
  tickets = $state<TicketInfo[]>([]);
  ticketsLoaded = $state(false);
  myPid = $state<string | null>(null);

  /** Último fallo de escritura, para que el invitado sepa qué pasó (A5). */
  error = $state<string | null>(null);

  private uid = '';
  private sid = '';
  private stopTickets: Array<() => void> = [];

  /** Tickets vivos por id, para poder fundir varias cuentas en una lista. */
  private ticketById = new Map<string, TicketInfo>();

  /** Listeners de líneas por ticket, para poder cortarlos si desaparece. */
  private stopLines = new Map<string, () => void>();

  /** Cuentas ya observadas: su listener de tickets se abre una sola vez. */
  private watchedAccounts = new Set<string>();

  /**
   * Envuelve una escritura para que un rechazo se VEA en vez de perderse en
   * una promesa sin capturar (A5).
   */
  private async write(action: () => Promise<void>): Promise<void> {
    try {
      this.error = null;
      await action();
    } catch (failure) {
      this.error = describeWriteError(failure);
    }
  }

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
          // El modo de reparto puede cambiar en caliente, y los tickets que
          // no lo declaran lo heredan de aquí: hay que repintarlos.
          this.publishTickets();
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
    await this.write(() =>
      updateDoc(doc(db, 'sessions', this.sid, 'settlements', settlementId), {
        state: 'marked',
        stateHistory: arrayUnion({
          state: 'marked',
          at: Timestamp.now(),
          by: 'guest',
        }),
        updatedAt: serverTimestamp(),
      }),
    );
  }

  /** Marca/desmarca un producto como suyo (modo byItem, sesión abierta). */
  async toggleLine(line: LineInfo): Promise<void> {
    if (!this.myPid) return;
    const pid = this.myPid;
    await this.write(() =>
      updateDoc(doc(db, line.path), {
        assignment: toggleSelf(line.assignment, pid),
      }),
    );
  }

  /** Fija MIS unidades reclamadas en una línea multi-unidad (P2.1). */
  async setLineUnits(line: LineInfo, units: number): Promise<void> {
    if (!this.myPid) return;
    const pid = this.myPid;
    await this.write(() =>
      updateDoc(doc(db, line.path), {
        assignment: setUnits(line.assignment, pid, units),
      }),
    );
  }

  /**
   * P2.2: cambia solo MI pertenencia a UNA unidad mediante ruta punteada.
   * Dos participantes editando la misma unidad no se sobrescriben; Firestore
   * fusiona campos distintos y las reglas verifican el pid y la unidad.
   */
  async setLineUnit(line: LineInfo, unit: number, selected: boolean): Promise<void> {
    if (!this.myPid) return;
    const pid = this.myPid;
    await this.write(() =>
      updateDoc(doc(db, line.path), unitUpdate(unit, pid, selected, deleteField())),
    );
  }

  /**
   * "Confirmar recepción": pending|marked → confirmed SOLO en las
   * liquidaciones donde este dispositivo reclama al RECEPTOR (la regla lo
   * garantiza). No exige que el deudor haya declarado nada antes: puede
   * haber pagado en mano y no abrir esto nunca (ADR-038).
   */
  async confirmReceived(settlementId: string): Promise<void> {
    await this.write(() =>
      updateDoc(doc(db, 'sessions', this.sid, 'settlements', settlementId), {
        state: 'confirmed',
        stateHistory: arrayUnion({
          state: 'confirmed',
          at: Timestamp.now(),
          by: 'receiver',
        }),
        updatedAt: serverTimestamp(),
      }),
    );
  }

  isMine(line: LineInfo): boolean {
    if (!this.myPid) return false;
    if (usesUnitModel(line.assignment)) {
      const units = Math.max(1, Math.floor(line.quantityMilli / 1000));
      return Array.from({ length: units }, (_, unit) => unit).some((unit) =>
        unitIsPickedBy(line.assignment, unit, this.myPid!),
      );
    }
    return isPickedBy(line.assignment, this.myPid);
  }

  /**
   * Tickets y líneas EN VIVO (A6).
   *
   * Antes esto era una foto única protegida por una guarda que nunca se
   * soltaba: un gasto añadido no aparecía, una corrección de total no se
   * veía, un cambio de modo dejaba la pestaña de productos mintiendo y un
   * gasto borrado seguía listado. Las líneas ya eran en vivo; lo que las
   * envolvía, no.
   */
  loadTickets(): void {
    if (this.ticketsLoaded) return;
    this.ticketsLoaded = true;

    this.stopTickets.push(
      onSnapshot(
        query(collection(db, 'sessions', this.sid, 'accounts'), orderBy('order')),
        (accounts) => {
          for (const account of accounts.docs) {
            if (this.watchedAccounts.has(account.id)) continue;
            this.watchedAccounts.add(account.id);
            const accountName = (account.data().name as string) ?? '';
            this.stopTickets.push(
              onSnapshot(collection(account.ref, 'tickets'), (tickets) => {
                this.mergeTickets(account.id, accountName, tickets);
              }),
            );
          }
        },
      ),
    );
  }

  /** Funde la foto viva de UNA cuenta en la lista global de tickets. */
  private mergeTickets(
    accountId: string,
    accountName: string,
    snapshot: { docs: Array<{ id: string; ref: { path: string }; data(): Record<string, unknown> }> },
  ): void {
    const vistos = new Set<string>();
    for (const ticket of snapshot.docs) {
      vistos.add(ticket.id);
      const info = ticketInfoFrom(
        ticket.id,
        accountId,
        ticket.data(),
        accountName,
        this.session?.splitModeDefault,
      );
      const previo = this.ticketById.get(ticket.id);
      this.ticketById.set(ticket.id, { ...info, lines: previo?.lines ?? [] });
      // El listener de líneas se abre UNA vez por ticket: es el que ya
      // existía y funcionaba, y sigue siendo el que deja ver elegir a los
      // demás en directo.
      if (!this.stopLines.has(ticket.id)) {
        this.stopLines.set(
          ticket.id,
          onSnapshot(
            query(collection(db, `${ticket.ref.path}/lines`), orderBy('order')),
            (snap) => {
              const actual = this.ticketById.get(ticket.id);
              if (!actual) return;
              actual.lines = snap.docs.map((d) => ({
                id: d.id,
                path: d.ref.path,
                name: (d.data().name as string) ?? '',
                quantityMilli: (d.data().quantityMilli as number) ?? 1000,
                totalPrice: (d.data().totalPrice as number) ?? 0,
                assignment: d.data().assignment as Assignment | undefined,
              }));
              this.publishTickets();
            },
          ),
        );
      }
    }
    // Un gasto borrado (A2) se va con su listener: si no, seguiría listado
    // y su suscripción viva contra un documento que ya no existe.
    for (const [id, info] of [...this.ticketById]) {
      if (info.accountId !== accountId || vistos.has(id)) continue;
      this.stopLines.get(id)?.();
      this.stopLines.delete(id);
      this.ticketById.delete(id);
    }
    this.publishTickets();
  }

  /**
   * Vuelca el mapa a la runa, en orden estable por cuenta y ticket.
   *
   * El modo efectivo se REDERIVA aquí, no se congela al leer el ticket: el
   * documento de sesión puede llegar después que los tickets, y también
   * puede cambiar de modo en caliente. Fijarlo una vez dejaba la pestaña de
   * productos decidida por una carrera de listeners.
   */
  private publishTickets(): void {
    this.tickets = [...this.ticketById.values()]
      .map((t) => ({
        ...t,
        pickable:
          (t.splitModeOverride ?? this.session?.splitModeDefault) === 'byItem',
      }))
      .sort(
        (a, b) =>
          a.accountId.localeCompare(b.accountId) || a.id.localeCompare(b.id),
      );
  }
}

export const guest = new GuestSession();
