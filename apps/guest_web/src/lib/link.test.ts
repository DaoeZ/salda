import { describe, expect, it } from 'vitest';

import { parseShareLink } from './link';

const CODE = 'SECRET-CODE-16CHARS';

describe('parseShareLink', () => {
  it('acepta el formato /s/{sid}#k={code}', () => {
    expect(parseShareLink('/s/abc123XYZ_-', `#k=${CODE}`)).toEqual({
      sessionId: 'abc123XYZ_-',
      shareCode: CODE,
    });
  });

  it('tolera barra final e ids cortos (la seguridad es del código)', () => {
    expect(parseShareLink('/s/abc123/', `#k=${CODE}`)?.sessionId).toBe(
      'abc123',
    );
    expect(parseShareLink('/s/e2e1', `#k=${CODE}`)?.sessionId).toBe('e2e1');
  });

  it('rechaza rutas ajenas, código ausente o corto', () => {
    expect(parseShareLink('/', `#k=${CODE}`)).toBeNull();
    expect(parseShareLink('/s/abc123', '')).toBeNull();
    expect(parseShareLink('/s/abc123', '#k=corto')).toBeNull();
    expect(parseShareLink('/otra/abc123', `#k=${CODE}`)).toBeNull();
  });
});
