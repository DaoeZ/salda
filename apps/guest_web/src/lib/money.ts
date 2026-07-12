/** Formato de importes es-ES. La web NUNCA calcula dinero (spec §5.3):
 * solo pinta céntimos que ya calculó la Cloud Function. */
const formatter = new Intl.NumberFormat('es-ES', {
  style: 'currency',
  currency: 'EUR',
});

export function formatCents(cents: number): string {
  return formatter.format(cents / 100);
}

/** `12,45 €` sin signo, para frases tipo "debes X". */
export function formatCentsAbs(cents: number): string {
  return formatCents(Math.abs(cents));
}
