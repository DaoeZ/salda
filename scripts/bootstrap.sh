#!/usr/bin/env bash
# Equivalente de scripts/bootstrap-windows.ps1 para Linux y macOS.
#
# Comprueba herramientas, instala dependencias y verifica que la firma de
# desarrollo es la de siempre. No despliega nada y no toca produccion.
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERDE=$'\033[32m'; ROJO=$'\033[31m'; AMARILLO=$'\033[33m'; CIAN=$'\033[36m'; FIN=$'\033[0m'

problemas=(); avisos=()
ok()    { printf '  %sOK   %s %s\n' "$VERDE" "$FIN" "$1"; }
falta() { printf '  %sFALTA%s %s\n' "$ROJO" "$FIN" "$1"; problemas+=("$1"); }
aviso() { printf '  %sAVISO%s %s\n' "$AMARILLO" "$FIN" "$1"; avisos+=("$1"); }
titulo(){ printf '\n%s%s%s\n' "$CIAN" "$1" "$FIN"; printf '%s\n' "${1//?/-}"; }

# La huella es publica (viaja en cada APK); lo secreto es la clave privada.
ESPERADA_SHA256='a844ab39c7d5f6ece56abca870ef865468fce053719a860a60403dfe27a9a0f4'
ESPERADO_ALIAS='salda-dev'

printf '\n%sBootstrap de Salda%s\nRepositorio: %s\n' "$CIAN" "$FIN" "$RAIZ"

titulo '1. Herramientas'
flutter_esperado=$(grep -o '"flutter"[^"]*"[^"]*"' "$RAIZ/.fvmrc" 2>/dev/null | grep -o '[0-9][0-9.]*' || true)
node_esperado=$(tr -d '[:space:]' < "$RAIZ/.nvmrc" 2>/dev/null || true)
java_esperado=$(tr -d '[:space:]' < "$RAIZ/.java-version" 2>/dev/null || true)

command -v git >/dev/null && ok "git $(git --version | grep -o '[0-9][0-9.]*' | head -1)" || falta 'git'

if command -v flutter >/dev/null; then
  v=$(flutter --version 2>/dev/null | grep -o 'Flutter [0-9][0-9.]*' | head -1 | cut -d' ' -f2)
  if [ -n "$flutter_esperado" ] && [ "$v" != "$flutter_esperado" ]; then
    aviso "flutter $v, pero el proyecto esta verificado con $flutter_esperado (.fvmrc)"
  else ok "flutter $v"; fi
else falta "flutter (se espera $flutter_esperado)"; fi

# Gradle usa JAVA_HOME, no el java del PATH.
if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ]; then
  vj=$("$JAVA_HOME/bin/java" -version 2>&1 | grep -o 'version "[0-9]*' | grep -o '[0-9]*' | head -1)
  if [ -n "$java_esperado" ] && [ "$vj" != "$java_esperado" ]; then
    aviso "JAVA_HOME es JDK $vj y el proyecto compila con $java_esperado (.java-version)"
  else ok "JAVA_HOME: JDK $vj"; fi
else falta 'JAVA_HOME (Gradle lo necesita; apunta a un JDK 17)'; fi

if command -v node >/dev/null; then
  vn=$(node -v | tr -d 'v')
  if [ -n "$node_esperado" ] && [ "${vn%%.*}" != "$node_esperado" ]; then
    aviso "node $vn; la CI usa la serie $node_esperado (.nvmrc)"
  else ok "node $vn"; fi
else falta "node (serie $node_esperado)"; fi

command -v npm >/dev/null && ok "npm $(npm -v)" || falta 'npm'
command -v firebase >/dev/null && ok "firebase-tools $(firebase --version)" \
  || aviso 'firebase-tools (npm i -g firebase-tools): hace falta para Rules y emuladores'

titulo '2. Configuracion privada (no viene de Git)'
if [ -f "$RAIZ/apps/mobile/android/dev-keystore.properties" ]; then
  ok 'dev-keystore.properties presente'
elif [ -n "${SALDA_DEV_KEYSTORE:-}" ]; then
  ok 'firma configurada por variables SALDA_DEV_*'
else
  falta 'dev-keystore.properties (copialo del respaldo privado; ver docs/SETUP_NUEVO_ORDENADOR.md)'
fi

for f in firebase.json .firebaserc \
         backend/firestore/firestore.rules \
         backend/firestore/firestore.indexes.json \
         backend/firestore/storage.rules \
         apps/mobile/lib/firebase_options.dart \
         apps/guest_web/public/.well-known/assetlinks.json; do
  [ -f "$RAIZ/$f" ] && ok "$f" || falta "$f (deberia venir de Git)"
done

if [ ${#problemas[@]} -gt 0 ]; then
  printf '\n%sFaltan requisitos:%s\n' "$ROJO" "$FIN"
  printf '  - %s\n' "${problemas[@]}"
  exit 1
fi

if [ "${1:-}" != "--skip-install" ]; then
  titulo '3. Dependencias'
  (cd "$RAIZ" && flutter pub get >/dev/null) && ok 'paquetes Dart/Flutter'
  for d in apps/guest_web backend/functions backend/firestore; do
    if [ -f "$RAIZ/$d/package-lock.json" ]; then
      # `ci` y no `install`: respeta el lockfile en vez de reescribirlo.
      (cd "$RAIZ/$d" && npm ci >/dev/null 2>&1) && ok "$d"
    fi
  done
fi

titulo '4. Firma de desarrollo'
props="$RAIZ/apps/mobile/android/dev-keystore.properties"
storeFile=$(grep -E '^\s*storeFile\s*=' "$props" 2>/dev/null | cut -d= -f2- | xargs || echo "${SALDA_DEV_KEYSTORE:-}")
storePass=$(grep -E '^\s*storePassword\s*=' "$props" 2>/dev/null | cut -d= -f2- | xargs || echo "${SALDA_DEV_KEYSTORE_PASSWORD:-}")
alias_=$(grep -E '^\s*keyAlias\s*=' "$props" 2>/dev/null | cut -d= -f2- | xargs || echo "${SALDA_DEV_KEY_ALIAS:-}")

if [ ! -f "$storeFile" ]; then
  printf '  %sMAL%s la keystore no existe en: %s\n' "$ROJO" "$FIN" "$storeFile"
  printf '  Copiala del respaldo privado. NO generes una nueva.\n'
  exit 1
fi
[ "$alias_" = "$ESPERADO_ALIAS" ] && ok "alias: $alias_" || { printf '  %sMAL%s alias %s != %s\n' "$ROJO" "$FIN" "$alias_" "$ESPERADO_ALIAS"; exit 1; }

huella=$(keytool -list -v -keystore "$storeFile" -alias "$alias_" -storepass "$storePass" 2>/dev/null \
  | grep -Eo 'SHA-?256:[0-9A-Fa-f: ]+' | head -1 | tr -d 'SHA-256: :' | tr '[:upper:]' '[:lower:]')
if [ "$huella" = "$ESPERADA_SHA256" ]; then
  ok 'SHA-256 del certificado coincide'
else
  printf '  %sMAL%s SHA-256 DISTINTO\n       esperado: %s\n       obtenido: %s\n' "$ROJO" "$FIN" "$ESPERADA_SHA256" "$huella"
  printf '  Una firma distinta rompe Google Sign-In, los App Links y la\n'
  printf '  actualizacion sobre la app instalada. No generes una clave nueva.\n'
  exit 1
fi

titulo '5. Analisis estatico'
(cd "$RAIZ" && dart analyze --fatal-infos) || exit 1
ok 'dart analyze --fatal-infos sin avisos'

printf '\n'
if [ ${#avisos[@]} -gt 0 ]; then
  printf '%sListo, con %d aviso(s):%s\n' "$AMARILLO" "${#avisos[@]}" "$FIN"
  printf '  - %s\n' "${avisos[@]}"
else
  printf '%sListo. Entorno preparado.%s\n' "$VERDE" "$FIN"
fi
printf '\nSiguientes pasos (docs/SETUP_NUEVO_ORDENADOR.md):\n'
printf '  flutter test            (desde apps/mobile)\n'
printf '  flutter build apk --debug --split-per-abi\n'
