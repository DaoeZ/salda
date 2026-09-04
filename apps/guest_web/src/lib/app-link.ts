export type AppLinkKind = 'g' | 't';

export interface AppLink {
  kind: AppLinkKind;
  token: string;
}

export interface AppLinkUrls extends AppLink {
  browserFallbackUrl: string;
  intentUrl: string;
  hasWebMarker: boolean;
}

const APP_LINK_PATH = /^\/(g|t)\/([A-Za-z0-9_-]+)\/?$/;
const APP_PACKAGE = 'dev.salda.salda_mobile';

function toUrl(value: URL | string): URL | null {
  try {
    return value instanceof URL ? new URL(value.href) : new URL(value);
  } catch {
    return null;
  }
}

export function parseAppLink(value: URL | string): AppLink | null {
  const url = toUrl(value);
  if (!url) return null;

  const match = url.pathname.match(APP_LINK_PATH);
  if (!match) return null;

  return {
    kind: match[1] as AppLinkKind,
    token: match[2],
  };
}

export function hasWebMarker(value: URL | string): boolean {
  const url = toUrl(value);
  return url?.searchParams.getAll('web').includes('1') ?? false;
}

export function buildAppLinkUrls(value: URL | string): AppLinkUrls | null {
  const url = toUrl(value);
  const appLink = url ? parseAppLink(url) : null;
  if (!url || !appLink) return null;

  const fallbackUrl = new URL(url.href);
  fallbackUrl.searchParams.set('web', '1');

  const intentTarget = new URL(url.href);
  intentTarget.hash = '';

  const intentUrl =
    `intent://${intentTarget.host}${intentTarget.pathname}${intentTarget.search}` +
    `#Intent;scheme=https;package=${APP_PACKAGE};` +
    `S.browser_fallback_url=${encodeURIComponent(fallbackUrl.href)};end`;

  return {
    ...appLink,
    browserFallbackUrl: fallbackUrl.href,
    intentUrl,
    hasWebMarker: hasWebMarker(url),
  };
}
