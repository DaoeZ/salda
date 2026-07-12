import { describe, expect, it } from 'vitest';

import { formatCents, formatCentsAbs } from './money';

// Intl es-ES usa espacio no separable (U+00A0) antes del símbolo.
const nbsp = ' ';

describe('formatCents', () => {
  it('formatea céntimos en es-ES', () => {
    expect(formatCents(1245)).toBe(`12,45${nbsp}€`);
    expect(formatCents(0)).toBe(`0,00${nbsp}€`);
    expect(formatCents(123456)).toBe(`1234,56${nbsp}€`);
  });

  it('formatCentsAbs quita el signo', () => {
    expect(formatCentsAbs(-730)).toBe(`7,30${nbsp}€`);
  });
});
