/**
 * A19: el contrato de escritura de la web tiene que ser EXACTAMENTE el mismo
 * que el de la app. Que divergieran fue el origen de A3, así que aquí se
 * fija literalmente la forma que verifican las Rules.
 */
import { describe, expect, it } from 'vitest';

import { pickingFinishUpdate, pickingOpenUpdate } from './assignment';

const BORRAR = Symbol('deleteField');

describe('contrato de picking (idéntico al de la app)', () => {
  it('reabrir declara el objetivo y lo pone en pendientes', () => {
    expect(pickingOpenUpdate('p2')).toEqual({
      'picking.lastTarget': 'p2',
      'picking.open.p2': true,
    });
  });

  it('terminar declara el objetivo y borra su entrada', () => {
    expect(pickingFinishUpdate('p2', BORRAR)).toEqual({
      'picking.lastTarget': 'p2',
      'picking.open.p2': BORRAR,
    });
  });

  it('solo toca UNA persona: es lo que exigen las Rules', () => {
    // `validPickingWrite` deniega si el diff afecta a más de un pid.
    expect(Object.keys(pickingOpenUpdate('p2'))).toHaveLength(2);
    expect(Object.keys(pickingFinishUpdate('p2', BORRAR))).toHaveLength(2);
  });
});
