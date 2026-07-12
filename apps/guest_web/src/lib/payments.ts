/** Botones de pago (RF-71): solo los métodos configurados por el anfitrión.
 * PayPal/Revolut abren enlace con importe; Bizum/IBAN son copiar+pegar. */
export interface PaymentMethods {
  bizumPhone?: string;
  paypalLink?: string;
  revolutTag?: string;
  iban?: string;
}

const euros = (cents: number) => (cents / 100).toFixed(2);

export function paypalUrl(link: string, cents: number): string {
  const base = link.replace(/\/+$/, '');
  const withHost = base.startsWith('http')
    ? base
    : `https://paypal.me/${base.replace(/^.*paypal\.me\//, '')}`;
  return `${withHost}/${euros(cents)}EUR`;
}

export function revolutUrl(tag: string, cents: number): string {
  const clean = tag.replace(/^@/, '').replace(/^.*revolut\.me\//, '');
  return `https://revolut.me/${clean}?amount=${euros(cents)}&currency=EUR`;
}

/** IBAN legible por bloques de 4. */
export function prettyIban(iban: string): string {
  return iban.replace(/\s+/g, '').replace(/(.{4})/g, '$1 ').trim();
}

export async function copyText(text: string): Promise<boolean> {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    return false;
  }
}
