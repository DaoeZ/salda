import { expect, it } from 'vitest';

import {
  buildAppLinkUrls,
  hasWebMarker,
  parseAppLink,
} from './app-link';
import { parseShareLink } from './link';

const ORIGIN = 'https://guest.salda.example';
const SHARE_CODE = 'SECRET-CODE-16CHARS';

const supportedPathCases = [
  {
    name: 'group token',
    path: '/g/GROUP_TOKEN-1',
    kind: 'g',
    token: 'GROUP_TOKEN-1',
  },
  {
    name: 'ticket token with trailing slash',
    path: '/t/TICKET_TOKEN-2/',
    kind: 't',
    token: 'TICKET_TOKEN-2',
  },
] as const;

it.each(supportedPathCases)('parses $name', ({ path, kind, token }) => {
  expect(parseAppLink(new URL(`${ORIGIN}${path}`))).toEqual({ kind, token });
});

const fallbackCases = [
  {
    name: '/g/TOKEN without query -> fallback ?web=1',
    path: '/g/TOKEN',
    fallback: '/g/TOKEN?web=1',
    hasWebMarker: false,
  },
  {
    name: '/g/TOKEN?utm_source=whatsapp preserves one query param',
    path: '/g/TOKEN?utm_source=whatsapp',
    fallback: '/g/TOKEN?utm_source=whatsapp&web=1',
    hasWebMarker: false,
  },
  {
    name: '/g/TOKEN?a=1&b=2 preserves multiple query params',
    path: '/g/TOKEN?a=1&b=2',
    fallback: '/g/TOKEN?a=1&b=2&web=1',
    hasWebMarker: false,
  },
  {
    name: '/g/TOKEN#fragment adds web in search and keeps fragment intact',
    path: '/g/TOKEN#fragment',
    fallback: '/g/TOKEN?web=1#fragment',
    hasWebMarker: false,
  },
  {
    name: '/g/TOKEN?web=1 reports one fallback marker',
    path: '/g/TOKEN?web=1',
    fallback: '/g/TOKEN?web=1',
    hasWebMarker: true,
  },
  {
    name: '/g/TOKEN?utm_source=wa&web=1 preserves query and marker',
    path: '/g/TOKEN?utm_source=wa&web=1',
    fallback: '/g/TOKEN?utm_source=wa&web=1',
    hasWebMarker: true,
  },
  {
    name: '/t/TOKEN preserves multiple query params',
    path: '/t/TOKEN?a=1&b=2',
    fallback: '/t/TOKEN?a=1&b=2&web=1',
    hasWebMarker: false,
  },
  {
    name: '/t/TOKEN preserves marker with query and fragment',
    path: '/t/TOKEN?utm_source=wa&web=1#receipt',
    fallback: '/t/TOKEN?utm_source=wa&web=1#receipt',
    hasWebMarker: true,
  },
] as const;

it.each(fallbackCases)('$name', ({ path, fallback, hasWebMarker: expectedMarker }) => {
  const urls = buildAppLinkUrls(new URL(`${ORIGIN}${path}`));

  expect(urls).not.toBeNull();
  expect(urls!.browserFallbackUrl).toBe(`${ORIGIN}${fallback}`);
  expect(urls!.hasWebMarker).toBe(expectedMarker);
  expect(new URL(urls!.browserFallbackUrl).searchParams.getAll('web')).toEqual(['1']);
});

const webMarkerCases = [
  {
    name: 'web=0 does not count as an attempted app open',
    path: '/g/TOKEN?web=0',
    fallback: '/g/TOKEN?web=1',
    hasWebMarker: false,
  },
  {
    name: 'duplicate web entries normalize to one fallback marker',
    path: '/g/TOKEN?web=1&web=1&source=share',
    fallback: '/g/TOKEN?web=1&source=share',
    hasWebMarker: true,
  },
] as const;

it.each(webMarkerCases)('$name', ({ path, fallback, hasWebMarker: expectedMarker }) => {
  const urls = buildAppLinkUrls(new URL(`${ORIGIN}${path}`));

  expect(urls).not.toBeNull();
  expect(urls!.hasWebMarker).toBe(expectedMarker);
  expect(urls!.browserFallbackUrl).toBe(`${ORIGIN}${fallback}`);
  expect(new URL(urls!.browserFallbackUrl).searchParams.getAll('web')).toEqual(['1']);
});

const webOnlyCases = [
  {
    name: '/s/SESSION with query and secret fragment',
    path: `/s/SESSION?utm_source=whatsapp#k=${SHARE_CODE}`,
  },
  {
    name: '/s/SESSION with fragment',
    path: `/s/SESSION#k=${SHARE_CODE}&view=summary`,
  },
] as const;

it.each(webOnlyCases)('$name stays web-only and preserves the secret', ({ path }) => {
  const currentUrl = new URL(`${ORIGIN}${path}`);

  expect(parseAppLink(currentUrl)).toBeNull();
  expect(buildAppLinkUrls(currentUrl)).toBeNull();
  expect(parseShareLink(currentUrl.pathname, currentUrl.hash)).toEqual({
    sessionId: 'SESSION',
    shareCode: SHARE_CODE,
  });
});

const invalidAppLinkCases = [
  { name: 'g token absent', path: '/g/' },
  { name: 't token absent', path: '/t/' },
  { name: 'g token invalid', path: '/g/not.valid' },
  { name: 't token invalid', path: '/t/not.valid' },
] as const;

it.each(invalidAppLinkCases)('$name never selects an intent', ({ path }) => {
  const currentUrl = new URL(`${ORIGIN}${path}`);

  expect(parseAppLink(currentUrl)).toBeNull();
  expect(buildAppLinkUrls(currentUrl)).toBeNull();
});

it('builds a valid intent with the original query and a complete decoded fallback', () => {
  const currentUrl = new URL(`${ORIGIN}/t/TOKEN?a=1&b=2#receipt`);
  const urls = buildAppLinkUrls(currentUrl);

  expect(urls).not.toBeNull();
  expect(urls!.intentUrl).toContain(
    'intent://guest.salda.example/t/TOKEN?a=1&b=2#Intent;scheme=https;package=dev.salda.salda_mobile;',
  );
  expect(urls!.intentUrl).not.toContain('#receipt#Intent;');

  const encodedFallback = urls!.intentUrl.match(
    /S\.browser_fallback_url=([^;]+);end$/,
  )?.[1];
  expect(encodedFallback).toBeDefined();

  const decodedFallback = decodeURIComponent(encodedFallback!);
  expect(decodedFallback).toBe(urls!.browserFallbackUrl);
  expect(new URL(decodedFallback).hash).toBe('#receipt');
  expect(hasWebMarker(new URL(decodedFallback))).toBe(true);
});
