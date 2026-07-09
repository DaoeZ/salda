/**
 * Branding de la web de invitados.
 *
 * Espejo mínimo de packages/design_tokens/assets/brand.json (fuente única).
 * Se mantiene a mano de momento porque solo son dos strings; si crece,
 * el generador de tokens lo emitirá también como .g.ts.
 */
export const BRAND = {
  appName: 'Salda',
  tagline: 'Escanea el ticket, reparte y salda cuentas.',
} as const;
