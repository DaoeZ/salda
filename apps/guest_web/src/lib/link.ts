/**
 * Enlace de invitación: https://<host>/s/{sessionId}#k={shareCode}
 * El código viaja en el fragment: no llega al servidor ni a logs (spec §13).
 */
export interface ShareLink {
  sessionId: string;
  shareCode: string;
}

export function parseShareLink(
  pathname: string,
  hash: string,
): ShareLink | null {
  // Cualquier id válido de Firestore; la seguridad la da el shareCode.
  const path = pathname.match(/^\/s\/([A-Za-z0-9_-]+)\/?$/);
  const code = new URLSearchParams(hash.replace(/^#/, '')).get('k');
  if (!path || !code || code.length < 16) return null;
  return { sessionId: path[1], shareCode: code };
}
