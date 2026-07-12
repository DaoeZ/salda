/** Identidad recordada por sesión (RF-62): "¿quién eres?" se pregunta UNA vez
 * por dispositivo. localStorage puede fallar (Safari privado): degradar sin romper. */
const key = (sessionId: string) => `salda.identity.${sessionId}`;

export function rememberedParticipant(sessionId: string): string | null {
  try {
    return localStorage.getItem(key(sessionId));
  } catch {
    return null;
  }
}

export function rememberParticipant(sessionId: string, pid: string): void {
  try {
    localStorage.setItem(key(sessionId), pid);
  } catch {
    /* sin persistencia: se volverá a preguntar */
  }
}

export function forgetParticipant(sessionId: string): void {
  try {
    localStorage.removeItem(key(sessionId));
  } catch {
    /* nada que olvidar */
  }
}
