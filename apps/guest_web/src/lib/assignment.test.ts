import { describe, expect, it } from 'vitest';

import {
  isPickedBy,
  myUnits,
  needsShareConfirmation,
  otherConsumers,
  setUnits,
  toggleSelf,
  unitConsumers,
  unitIsPickedBy,
  unitsForQuantity,
  usesUnitModel,
} from './assignment';

describe('toggleSelf (contrato con las reglas de Firestore)', () => {
  it('marcarse en línea vacía → one con peso 1 y lastEditorPid', () => {
    const result = toggleSelf({ type: 'unassigned', participants: {} }, 'p2');
    expect(result).toEqual({
      type: 'one',
      participants: { p2: 1 },
      lastEditorPid: 'p2',
    });
  });

  it('marcarse donde ya hay otro → shared sin tocar la otra entrada', () => {
    const result = toggleSelf(
      { type: 'one', participants: { p3: 1 } },
      'p2',
    );
    expect(result.type).toBe('shared');
    expect(result.participants).toEqual({ p3: 1, p2: 1 });
  });

  it('desmarcarse → desaparece SOLO su entrada', () => {
    const result = toggleSelf(
      { type: 'shared', participants: { p2: 1, p3: 2 } },
      'p2',
    );
    expect(result).toEqual({
      type: 'one',
      participants: { p3: 2 },
      lastEditorPid: 'p2',
    });
  });

  it('el último en salir deja la línea unassigned', () => {
    const result = toggleSelf({ type: 'one', participants: { p2: 1 } }, 'p2');
    expect(result.type).toBe('unassigned');
    expect(result.participants).toEqual({});
  });

  it('assignment ausente se trata como vacío', () => {
    expect(toggleSelf(undefined, 'p2').participants).toEqual({ p2: 1 });
  });

  it('isPickedBy', () => {
    expect(isPickedBy({ type: 'one', participants: { p2: 1 } }, 'p2')).toBe(
      true,
    );
    expect(isPickedBy(undefined, 'p2')).toBe(false);
  });
});

describe('flujo de compartir (nunca duplica líneas)', () => {
  it('otherConsumers excluye al propio pid', () => {
    expect(
      otherConsumers({ type: 'shared', participants: { p2: 1, p3: 1 } }, 'p2'),
    ).toEqual(['p3']);
    expect(otherConsumers(undefined, 'p2')).toEqual([]);
  });

  it('pide confirmar SOLO si otro ya lo cogió y yo no estoy', () => {
    // Otro (p3) ya lo tiene, yo (p2) no → preguntar.
    expect(
      needsShareConfirmation({ type: 'one', participants: { p3: 1 } }, 'p2'),
    ).toBe(true);
    // Línea libre → sumarme directo, sin preguntar.
    expect(needsShareConfirmation(undefined, 'p2')).toBe(false);
    expect(
      needsShareConfirmation({ type: 'unassigned', participants: {} }, 'p2'),
    ).toBe(false);
    // Ya es mía (quitármela) → nunca preguntar.
    expect(
      needsShareConfirmation({ type: 'one', participants: { p2: 1 } }, 'p2'),
    ).toBe(false);
    // Ya compartida conmigo dentro → no preguntar.
    expect(
      needsShareConfirmation(
        { type: 'shared', participants: { p2: 1, p3: 1 } },
        'p2',
      ),
    ).toBe(false);
  });

  it('compartir = un único producto con varios consumidores (no duplica)', () => {
    // p3 lo tenía; p2 confirma compartir → toggleSelf añade SOLO su entrada.
    const before = { type: 'one' as const, participants: { p3: 1 } };
    const after = toggleSelf(before, 'p2');
    expect(after.type).toBe('shared');
    expect(after.participants).toEqual({ p3: 1, p2: 1 });
    expect(after.lastEditorPid).toBe('p2'); // exigido por las reglas
    // Sigue siendo UNA línea: mismo objeto de asignación, dos consumidores.
    expect(Object.keys(after.participants!)).toHaveLength(2);
  });
});

describe('unidades (P2.1)', () => {
  it('unitsForQuantity: enteros ≥2 son unidades; pesos y unidad simple, 1', () => {
    expect(unitsForQuantity(1000)).toBe(1);
    expect(unitsForQuantity(2000)).toBe(2);
    expect(unitsForQuantity(5000)).toBe(5);
    expect(unitsForQuantity(466)).toBe(1); // 0,466 kg
    expect(unitsForQuantity(2500)).toBe(1); // 2,5 no es entero
  });

  it('setUnits fija SOLO mi entrada con el nº de unidades', () => {
    const result = setUnits(
      { type: 'one', participants: { p3: 1 } },
      'p2',
      2,
    );
    expect(result).toEqual({
      type: 'shared',
      participants: { p3: 1, p2: 2 },
      lastEditorPid: 'p2',
    });
  });

  it('setUnits a 0 me quita sin tocar a los demás', () => {
    const result = setUnits(
      { type: 'shared', participants: { p2: 2, p3: 1 } },
      'p2',
      0,
    );
    expect(result).toEqual({
      type: 'one',
      participants: { p3: 1 },
      lastEditorPid: 'p2',
    });
  });

  it('toggleSelf es setUnits(1)/setUnits(0): contrato intacto', () => {
    expect(toggleSelf(undefined, 'p2')).toEqual(
      setUnits(undefined, 'p2', 1),
    );
    expect(
      toggleSelf({ type: 'one', participants: { p2: 2 } }, 'p2'),
    ).toEqual(setUnits({ type: 'one', participants: { p2: 2 } }, 'p2', 0));
  });

  it('myUnits lee mi peso (0 si no estoy)', () => {
    expect(myUnits({ type: 'one', participants: { p2: 2 } }, 'p2')).toBe(2);
    expect(myUnits(undefined, 'p2')).toBe(0);
  });
});

describe('unidades físicas (P2.2)', () => {
  const assignment = {
    type: 'units' as const,
    schemaVersion: 2,
    units: {
      u0: { edgar: true },
      u1: { edgar: true, alba: true },
    },
  };

  it('cada índice conserva consumidores independientes', () => {
    expect(usesUnitModel(assignment)).toBe(true);
    expect(usesUnitModel({ type: 'units' })).toBe(false);
    expect(usesUnitModel({ type: 'shared', schemaVersion: 2 })).toBe(false);
    expect(unitConsumers(assignment, 0)).toEqual(['edgar']);
    expect(unitConsumers(assignment, 1)).toEqual(['edgar', 'alba']);
    expect(unitConsumers(assignment, 2)).toEqual([]);
  });

  it('dos personas pueden seleccionar la misma unidad sin duplicarla', () => {
    expect(unitIsPickedBy(assignment, 1, 'edgar')).toBe(true);
    expect(unitIsPickedBy(assignment, 1, 'alba')).toBe(true);
    expect(unitIsPickedBy(assignment, 0, 'alba')).toBe(false);
    expect(Object.keys(assignment.units)).toHaveLength(2);
  });

  it('el modelo histórico sigue detectándose como histórico', () => {
    expect(usesUnitModel({ type: 'shared', participants: { edgar: 2, alba: 1 } }))
      .toBe(false);
  });
});
