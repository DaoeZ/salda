import { describe, expect, it } from 'vitest';

import { isPickedBy, toggleSelf } from './assignment';

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
