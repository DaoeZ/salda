import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

describe('frontera económica de la web', () => {
  it('no estima importes por persona desde las líneas', () => {
    const source = readFileSync(
      new URL('../views/PickItems.svelte', import.meta.url),
      'utf8',
    );

    expect(source).not.toMatch(/totalPrice\s*\//);
    expect(source).not.toContain('Math.round(line.totalPrice');
    expect(source).not.toContain(' c/u');
  });
});
