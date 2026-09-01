/**
 * Lógica pura del estado del invitado: la ficha de un ticket (A6) y el
 * mensaje de una escritura rechazada (A5). Ambas se extrajeron de la clase
 * precisamente para poder probarlas sin Firestore de por medio.
 */
import { describe, expect, it } from 'vitest';

import { describeWriteError, ticketInfoFrom } from './session.svelte';

describe('ficha de ticket (A6)', () => {
  it('el modo efectivo lo decide el ticket y, si no, la sesión', () => {
    // El ticket manda sobre la sesión.
    expect(
      ticketInfoFrom('t1', 'a1', { splitModeOverride: 'byItem' }, 'Cena', 'equal')
        .pickable,
    ).toBe(true);
    // Sin override, hereda el de la sesión.
    expect(ticketInfoFrom('t1', 'a1', {}, 'Cena', 'byItem').pickable).toBe(true);
    expect(ticketInfoFrom('t1', 'a1', {}, 'Cena', 'equal').pickable).toBe(false);
  });

  it('el nombre cae al de la cuenta cuando el comercio no se leyó', () => {
    expect(ticketInfoFrom('t1', 'a1', {}, 'Cena', 'equal').merchantName).toBe(
      'Cena',
    );
    expect(
      ticketInfoFrom('t1', 'a1', { merchant: { name: 'Bar' } }, 'Cena', 'equal')
        .merchantName,
    ).toBe('Bar');
  });

  it('conserva la cuenta a la que pertenece', () => {
    expect(ticketInfoFrom('t1', 'a2', {}, 'Cena', 'equal').accountId).toBe('a2');
  });

  // El modo se REDERIVA al publicar, no se congela: el documento de sesión
  // puede llegar después que los tickets. Por eso el override viaja aparte.
  it('conserva el override para poder rederivar el modo más tarde', () => {
    expect(ticketInfoFrom('t1', 'a1', {}, 'Cena', undefined).splitModeOverride)
      .toBeUndefined();
    expect(
      ticketInfoFrom('t1', 'a1', { splitModeOverride: 'byItem' }, 'Cena', undefined)
        .splitModeOverride,
    ).toBe('byItem');
    // Sin sesión todavía, un ticket sin override no es seleccionable.
    expect(ticketInfoFrom('t1', 'a1', {}, 'Cena', undefined).pickable).toBe(false);
  });
});

describe('mensajes de escritura rechazada (A5)', () => {
  it('permiso denegado explica que la selección no se guardó', () => {
    expect(describeWriteError({ code: 'permission-denied' })).toMatch(
      /no se pudo guardar/i,
    );
  });

  it('cualquier otro fallo habla de conexión', () => {
    expect(describeWriteError({ code: 'unavailable' })).toMatch(/conexión/i);
    expect(describeWriteError(new Error('boom'))).toMatch(/conexión/i);
  });
});
