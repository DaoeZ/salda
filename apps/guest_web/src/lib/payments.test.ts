import { describe, expect, it } from 'vitest';

import { paypalUrl, prettyIban, revolutUrl } from './payments';

describe('enlaces de pago', () => {
  it('paypal: usuario suelto, enlace paypal.me o URL completa', () => {
    expect(paypalUrl('edgar', 1245)).toBe('https://paypal.me/edgar/12.45EUR');
    expect(paypalUrl('paypal.me/edgar', 1245)).toBe(
      'https://paypal.me/edgar/12.45EUR',
    );
    expect(paypalUrl('https://paypal.me/edgar/', 500)).toBe(
      'https://paypal.me/edgar/5.00EUR',
    );
  });

  it('revolut: tag con o sin @', () => {
    expect(revolutUrl('@edgar', 730)).toBe(
      'https://revolut.me/edgar?amount=7.30&currency=EUR',
    );
    expect(revolutUrl('revolut.me/edgar', 730)).toContain('/edgar?');
  });

  it('iban en bloques de 4', () => {
    expect(prettyIban('ES9121000418450200051332')).toBe(
      'ES91 2100 0418 4502 0005 1332',
    );
  });
});
