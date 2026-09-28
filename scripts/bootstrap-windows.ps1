<#
.SYNOPSIS
  Prepara un ordenador Windows recién clonado para trabajar en Salda.

.DESCRIPTION
  Comprueba herramientas, instala las dependencias del proyecto y verifica
  que la firma de desarrollo es la de siempre. No despliega nada, no toca
  producción y no modifica ninguna versión de dependencia.

  Es idempotente: se puede ejecutar tantas veces como haga falta.

.PARAMETER SkipInstall
  Solo diagnostica: no instala dependencias.

.EXAMPLE
  pwsh scripts/bootstrap-windows.ps1
#>
[CmdletBinding()]
param(
  [switch]$SkipInstall
)

$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot

$problemas = New-Object System.Collections.Generic.List[string]
$avisos = New-Object System.Collections.Generic.List[string]
function Ok($m) { Write-Host "  OK    $m" -ForegroundColor Green }
function Falta($m) { Write-Host "  FALTA $m" -ForegroundColor Red; $script:problemas.Add($m) }
function Aviso($m) { Write-Host "  AVISO $m" -ForegroundColor Yellow; $script:avisos.Add($m) }
function Titulo($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) }

function Version-De([string]$exe, [string[]]$argumentos, [string]$patron) {
  if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) { return $null }
  # Se invoca por NOMBRE, no por `.Source`: para npm y firebase, Get-Command
  # devuelve el envoltorio `.ps1`, y `cmd` no sabe ejecutarlo — se queda
  # colgado esperando. Por nombre, cmd resuelve el `.cmd` via PATHEXT.
  #
  # Y se pasa por cmd, y no directamente, porque varias de estas herramientas
  # escriben la version en stderr: en PowerShell 5.1, `2>&1` sobre un exe
  # nativo envuelve cada linea en un ErrorRecord y aborta con
  # NativeCommandError.
  $salida = (cmd /c "$exe $($argumentos -join ' ') 2>&1") -join "`n"
  $m = [regex]::Match($salida, $patron)
  if ($m.Success) { return $m.Groups[1].Value }
  return '?'
}

Write-Host ''
Write-Host 'Bootstrap de Salda (Windows)' -ForegroundColor Cyan
Write-Host "Repositorio: $raiz"

# ── 1. Herramientas ──────────────────────────────────────────────────────
Titulo '1. Herramientas'

# Las versiones ESPERADAS salen de los archivos versionados, no de constantes
# escritas aqui: asi no hay dos fuentes de verdad que se desincronicen.
$flutterEsperado = $null
$fvmrc = Join-Path $raiz '.fvmrc'
if (Test-Path $fvmrc) {
  $flutterEsperado = (Get-Content $fvmrc -Raw | ConvertFrom-Json).flutter
}
$nodeEsperado = if (Test-Path (Join-Path $raiz '.nvmrc')) { (Get-Content (Join-Path $raiz '.nvmrc') -Raw).Trim() } else { $null }
$javaEsperado = if (Test-Path (Join-Path $raiz '.java-version')) { (Get-Content (Join-Path $raiz '.java-version') -Raw).Trim() } else { $null }

$git = Version-De 'git' @('--version') 'git version ([\d.]+)'
if ($git) { Ok "git $git" } else { Falta 'git' }

$flutter = Version-De 'flutter' @('--version') 'Flutter ([\d.]+)'
if (-not $flutter) {
  Falta "flutter (se espera $flutterEsperado; instalalo y anadelo al PATH)"
} elseif ($flutterEsperado -and $flutter -ne $flutterEsperado) {
  Aviso "flutter $flutter, pero el proyecto esta verificado con $flutterEsperado (.fvmrc)"
} else {
  Ok "flutter $flutter"
}

$dart = Version-De 'dart' @('--version') 'Dart SDK version: ([\d.]+)'
if ($dart) { Ok "dart $dart" } else { Aviso 'dart no esta en el PATH (viene con Flutter)' }

# Gradle usa JAVA_HOME, no el java del PATH: es el que hay que comprobar.
$javaHome = $env:JAVA_HOME
if (-not $javaHome) {
  Falta 'JAVA_HOME (Gradle lo necesita; apunta a un JDK 17)'
} elseif (-not (Test-Path (Join-Path $javaHome 'bin/java.exe'))) {
  Falta "JAVA_HOME apunta a algo que no es un JDK: $javaHome"
} else {
  # `java -version` escribe en stderr. En PowerShell 5.1, redirigir el stderr
  # de un exe nativo con 2>&1 envuelve cada linea en un ErrorRecord y aborta
  # con NativeCommandError: se captura a traves de cmd para evitarlo.
  $exeJava = Join-Path $javaHome 'bin/java.exe'
  $vJava = (cmd /c "`"$exeJava`" -version 2>&1") -join "`n"
  $mj = [regex]::Match($vJava, 'version "(\d+)')
  $mayor = if ($mj.Success) { $mj.Groups[1].Value } else { '?' }
  if ($javaEsperado -and $mayor -ne $javaEsperado) {
    Aviso "JAVA_HOME es JDK $mayor y el proyecto compila con $javaEsperado (.java-version)"
  } else {
    Ok "JAVA_HOME: JDK $mayor"
  }
}

$node = Version-De 'node' @('-v') 'v?([\d.]+)'
if (-not $node) {
  Falta "node (se espera la serie $nodeEsperado)"
} else {
  $mayorNode = $node.Split('.')[0]
  if ($nodeEsperado -and $mayorNode -ne $nodeEsperado) {
    Aviso "node $node; la CI usa la serie $nodeEsperado (.nvmrc)"
  } else {
    Ok "node $node"
  }
}

$npm = Version-De 'npm' @('-v') '([\d.]+)'
if ($npm) { Ok "npm $npm" } else { Falta 'npm' }

$firebase = Version-De 'firebase' @('--version') '([\d.]+)'
if ($firebase) { Ok "firebase-tools $firebase" } else { Aviso 'firebase-tools (npm i -g firebase-tools): hace falta para Rules y emuladores' }

$sdk = $env:ANDROID_HOME; if (-not $sdk) { $sdk = $env:ANDROID_SDK_ROOT }
if ($sdk -and (Test-Path $sdk)) {
  $bt = Get-ChildItem (Join-Path $sdk 'build-tools') -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -First 1
  if ($bt) { Ok "Android SDK: $sdk (build-tools $($bt.Name))" }
  else { Aviso "Android SDK sin build-tools: $sdk" }
} else {
  Falta 'ANDROID_HOME (Android SDK). Sin el no hay APK ni apksigner'
}

# ── 2. Configuración privada ─────────────────────────────────────────────
Titulo '2. Configuracion privada (no viene de Git)'

$devProps = Join-Path $raiz 'apps/mobile/android/dev-keystore.properties'
if (Test-Path $devProps) {
  Ok 'dev-keystore.properties presente'
} elseif ($env:SALDA_DEV_KEYSTORE) {
  Ok 'firma configurada por variables SALDA_DEV_*'
} else {
  Falta 'dev-keystore.properties (copialo del respaldo privado; ver docs/SETUP_NUEVO_ORDENADOR.md)'
}

$localProps = Join-Path $raiz 'apps/mobile/android/local.properties'
if (Test-Path $localProps) {
  Ok 'local.properties presente'
} elseif ($flutter) {
  # Lo genera el propio `flutter pub get`; no es un secreto ni se versiona.
  Aviso 'local.properties no existe todavia; lo creara Flutter al compilar'
}

foreach ($f in @(
  'firebase.json', '.firebaserc',
  'backend/firestore/firestore.rules',
  'backend/firestore/firestore.indexes.json',
  'backend/firestore/storage.rules',
  'apps/mobile/lib/firebase_options.dart',
  'apps/guest_web/public/.well-known/assetlinks.json'
)) {
  if (Test-Path (Join-Path $raiz $f)) { Ok "$f" } else { Falta "$f (deberia venir de Git)" }
}

# `google-services.json` NO hace falta: el plugin com.google.gms.google-services
# no se aplica y la configuracion de cliente viaja en firebase_options.dart
# (ADR-016). Se comprueba solo para no perder tiempo buscandolo.
$gsj = Join-Path $raiz 'apps/mobile/android/app/google-services.json'
if (Test-Path $gsj) {
  Ok 'google-services.json presente (opcional: no lo usa el build)'
} else {
  Ok 'google-services.json no hace falta (config en firebase_options.dart)'
}

if ($problemas.Count -gt 0) {
  Write-Host ''
  Write-Host 'Faltan requisitos. Resuelvelos y vuelve a ejecutar:' -ForegroundColor Red
  $problemas | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
  exit 1
}

# ── 3. Dependencias ──────────────────────────────────────────────────────
if (-not $SkipInstall) {
  Titulo '3. Dependencias'
  Push-Location $raiz
  try {
    Write-Host '  flutter pub get (workspace completo)...'
    & flutter pub get | Out-Null
    if ($LASTEXITCODE -ne 0) { Falta 'flutter pub get fallo'; exit 1 }
    Ok 'paquetes Dart/Flutter'

    foreach ($dir in @('apps/guest_web', 'backend/functions', 'backend/firestore')) {
      $ruta = Join-Path $raiz $dir
      if (Test-Path (Join-Path $ruta 'package-lock.json')) {
        Write-Host "  npm ci en $dir (puede tardar)..."
        # `ci` y no `install`: respeta el lockfile en vez de reescribirlo.
        #
        # Se invoca por `cmd` y con la salida a un log: npm escribe el
        # progreso por stderr y, en PowerShell 5.1, `2>&1 | Out-Null` sobre
        # un .cmd puede quedarse colgado indefinidamente.
        $log = Join-Path $env:TEMP "salda-npm-$($dir -replace '[\\/]','-').log"
        cmd /c "npm ci --prefix `"$ruta`" > `"$log`" 2>&1"
        if ($LASTEXITCODE -ne 0) {
          Falta "npm ci fallo en $dir (detalles en $log)"
          exit 1
        }
        Ok "$dir"
      }
    }
  } finally { Pop-Location }
}

# ── 4. Firma ─────────────────────────────────────────────────────────────
Titulo '4. Firma de desarrollo'
& (Join-Path $PSScriptRoot 'verify-signing-key.ps1')
if ($LASTEXITCODE -ne 0) {
  Write-Host ''
  Write-Host 'La firma NO es la correcta: no compiles APKs hasta arreglarlo.' -ForegroundColor Red
  exit 1
}

# ── 5. Comprobación rápida ───────────────────────────────────────────────
Titulo '5. Analisis estatico'
Push-Location $raiz
try {
  & dart analyze --fatal-infos
  if ($LASTEXITCODE -ne 0) { Write-Host '  El analisis ha fallado.' -ForegroundColor Red; exit 1 }
  Ok 'dart analyze --fatal-infos sin avisos'
} finally { Pop-Location }

Write-Host ''
if ($avisos.Count -gt 0) {
  Write-Host "Listo, con $($avisos.Count) aviso(s):" -ForegroundColor Yellow
  $avisos | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
} else {
  Write-Host 'Listo. Entorno preparado.' -ForegroundColor Green
}
Write-Host ''
Write-Host 'Siguientes pasos (docs/SETUP_NUEVO_ORDENADOR.md):' -ForegroundColor Cyan
Write-Host '  flutter test            (desde apps/mobile)'
Write-Host '  flutter build apk --debug --split-per-abi'
Write-Host '  pwsh scripts/verify-signing-key.ps1 -Apk <ruta del arm64>'
exit 0
