<#
.SYNOPSIS
  Comprueba que este ordenador firma con LA MISMA clave de desarrollo de
  siempre, no con una nueva.

.DESCRIPTION
  Una clave distinta parece funcionar —el APK compila e instala en un móvil
  limpio— pero rompe tres cosas a la vez y ninguna avisa con claridad:

    · Google Sign-In falla con DEVELOPER_ERROR, porque el cliente OAuth de
      Android se autoriza por (paquete + SHA-1) y la huella nueva no está
      registrada en Firebase.
    · Los App Links dejan de abrir la app: se verifican contra el SHA-256
      publicado en assetlinks.json.
    · Android trata el APK como otra aplicación: no actualiza sobre la
      instalada, así que se pierde la identidad local del invitado.

  Por eso este script devuelve código de salida distinto de cero en cuanto
  algo no coincide, y NUNCA imprime contraseñas.

.PARAMETER Apk
  Ruta de un APK a verificar además del keystore. Opcional.

.EXAMPLE
  pwsh scripts/verify-signing-key.ps1
  pwsh scripts/verify-signing-key.ps1 -Apk apps/mobile/build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk
#>
[CmdletBinding()]
param(
  [string]$Apk
)

$ErrorActionPreference = 'Stop'

# Huella del certificado de desarrollo compartido. Es pública por naturaleza
# (viaja dentro de cada APK y en assetlinks.json); lo secreto es la clave
# privada del keystore, que no aparece por ningún lado.
$ESPERADA_SHA256 = 'a844ab39c7d5f6ece56abca870ef865468fce053719a860a60403dfe27a9a0f4'
$ESPERADO_ALIAS = 'salda-dev'
$ESPERADO_APPID = 'dev.salda.salda_mobile'
$ESPERADO_DN = 'CN=Salda Development'

$raiz = Split-Path -Parent $PSScriptRoot
$androidDir = Join-Path $raiz 'apps/mobile/android'
$propsFile = Join-Path $androidDir 'dev-keystore.properties'

$fallos = New-Object System.Collections.Generic.List[string]
function Ok($m) { Write-Host "  OK   $m" -ForegroundColor Green }
function Mal($m) { Write-Host "  MAL  $m" -ForegroundColor Red; $script:fallos.Add($m) }
function Info($m) { Write-Host "  ...  $m" -ForegroundColor DarkGray }

function Normaliza([string]$huella) {
  return ($huella -replace '[^0-9a-fA-F]', '').ToLowerInvariant()
}

Write-Host ''
Write-Host 'Verificacion de la firma de desarrollo de Salda' -ForegroundColor Cyan
Write-Host '----------------------------------------------'

# ── 1. Configuración local ───────────────────────────────────────────────
# El archivo tiene prioridad sobre las variables (igual que en build.gradle.kts).
$storeFile = $null; $storePass = $null; $alias = $null
if (Test-Path $propsFile) {
  Info "configuracion: $propsFile"
  foreach ($linea in Get-Content $propsFile) {
    if ($linea -match '^\s*storeFile\s*=\s*(.+)$') { $storeFile = $Matches[1].Trim() }
    if ($linea -match '^\s*storePassword\s*=\s*(.+)$') { $storePass = $Matches[1].Trim() }
    if ($linea -match '^\s*keyAlias\s*=\s*(.+)$') { $alias = $Matches[1].Trim() }
  }
} else {
  Info 'sin dev-keystore.properties; probando variables SALDA_DEV_*'
  $storeFile = $env:SALDA_DEV_KEYSTORE
  $storePass = $env:SALDA_DEV_KEYSTORE_PASSWORD
  $alias = $env:SALDA_DEV_KEY_ALIAS
}

if (-not $storeFile) {
  Mal 'no hay configuracion de firma (ni dev-keystore.properties ni SALDA_DEV_KEYSTORE)'
  Write-Host ''
  Write-Host 'Restaura el respaldo privado siguiendo docs/SETUP_NUEVO_ORDENADOR.md.' -ForegroundColor Yellow
  exit 1
}
Ok "storeFile declarado: $storeFile"

if (-not (Test-Path $storeFile)) {
  Mal "la keystore NO existe en la ruta declarada: $storeFile"
  Write-Host ''
  Write-Host 'Copia salda-dev.jks desde el respaldo privado. No generes una nueva.' -ForegroundColor Yellow
  exit 1
}
$hashKs = (Get-FileHash $storeFile -Algorithm SHA256).Hash.ToLowerInvariant()
Ok "keystore presente (sha256 $($hashKs.Substring(0,16))...)"

if ($alias -ne $ESPERADO_ALIAS) {
  Mal "alias '$alias' distinto del esperado '$ESPERADO_ALIAS'"
} else {
  Ok "alias: $alias"
}

# ── 2. Certificado del keystore ──────────────────────────────────────────
if (-not (Get-Command keytool -ErrorAction SilentlyContinue)) {
  Mal 'keytool no esta en el PATH (instala un JDK 17)'
} elseif (-not $storePass) {
  Mal 'falta storePassword: no se puede leer el certificado'
} else {
  # 2>&1 sobre un exe nativo ensucia $? en PowerShell 5.1: se ignora el
  # codigo y se decide por el contenido.
  $salida = & keytool -list -v -keystore $storeFile -alias $alias -storepass $storePass 2>&1 | Out-String
  $m = [regex]::Match($salida, 'SHA-?256:\s*([0-9A-Fa-f:]+)')
  if (-not $m.Success) {
    Mal 'no se pudo leer el certificado (contrasena incorrecta o alias inexistente)'
  } else {
    $sha256 = Normaliza $m.Groups[1].Value
    if ($sha256 -eq $ESPERADA_SHA256) {
      Ok "SHA-256 del certificado coincide"
    } else {
      Mal "SHA-256 DISTINTO`n         esperado: $ESPERADA_SHA256`n         obtenido: $sha256"
    }
    $m1 = [regex]::Match($salida, 'SHA-?1:\s*([0-9A-Fa-f:]+)')
    if ($m1.Success) { Info "SHA-1: $($m1.Groups[1].Value)" }
    if ($salida -match [regex]::Escape($ESPERADO_DN)) {
      Ok "titular: $ESPERADO_DN ..."
    } else {
      Mal "el titular del certificado no es '$ESPERADO_DN ...'"
    }
  }
}

# ── 3. applicationId ─────────────────────────────────────────────────────
$gradle = Join-Path $androidDir 'app/build.gradle.kts'
if ((Get-Content $gradle -Raw) -match "applicationId\s*=\s*`"$([regex]::Escape($ESPERADO_APPID))`"") {
  Ok "applicationId: $ESPERADO_APPID"
} else {
  Mal "applicationId distinto de $ESPERADO_APPID en app/build.gradle.kts"
}

# ── 4. assetlinks.json ───────────────────────────────────────────────────
# Se lee el que se PUBLICA, no el de dist/ (que es un artefacto de build).
$assetlinks = Join-Path $raiz 'apps/guest_web/public/.well-known/assetlinks.json'
if (Test-Path $assetlinks) {
  $contenido = Normaliza ((Get-Content $assetlinks -Raw))
  if ($contenido.Contains($ESPERADA_SHA256)) {
    Ok 'la huella sigue declarada en assetlinks.json (App Links intactos)'
  } else {
    Mal 'la huella NO esta en assetlinks.json: los App Links no abririan la app'
  }
  if ((Get-Content $assetlinks -Raw) -match [regex]::Escape($ESPERADO_APPID)) {
    Ok 'assetlinks.json declara el paquete correcto'
  } else {
    Mal 'assetlinks.json no declara dev.salda.salda_mobile'
  }
} else {
  Info 'assetlinks.json no encontrado localmente (se omite esa comprobacion)'
}

# ── 5. APK, si se ha pedido ──────────────────────────────────────────────
if ($Apk) {
  if (-not (Test-Path $Apk)) {
    Mal "el APK indicado no existe: $Apk"
  } else {
    $sdk = $env:ANDROID_HOME; if (-not $sdk) { $sdk = $env:ANDROID_SDK_ROOT }
    $signer = $null
    if ($sdk) {
      $bt = Get-ChildItem (Join-Path $sdk 'build-tools') -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
      if ($bt) { $signer = Join-Path $bt.FullName 'apksigner.bat' }
    }
    if (-not $signer -or -not (Test-Path $signer)) {
      Mal 'no se encontro apksigner (falta ANDROID_HOME o las build-tools)'
    } else {
      $salidaApk = & $signer verify --print-certs $Apk 2>&1 | Out-String
      $ma = [regex]::Match($salidaApk, 'certificate SHA-?256 digest:\s*([0-9A-Fa-f]+)')
      if (-not $ma.Success) {
        Mal "apksigner no pudo verificar $Apk"
      } elseif ((Normaliza $ma.Groups[1].Value) -eq $ESPERADA_SHA256) {
        Ok "el APK esta firmado con la clave correcta"
      } else {
        Mal "el APK esta firmado con OTRA clave: $(Normaliza $ma.Groups[1].Value)"
      }
    }
  }
}

Write-Host ''
if ($fallos.Count -gt 0) {
  Write-Host "FALLA la verificacion ($($fallos.Count) problema(s))." -ForegroundColor Red
  Write-Host 'NO compiles APKs para instalar hasta resolverlo: una firma distinta' -ForegroundColor Yellow
  Write-Host 'rompe Google Sign-In, los App Links y la actualizacion sobre la app' -ForegroundColor Yellow
  Write-Host 'ya instalada. No generes una clave nueva: restaura la existente.' -ForegroundColor Yellow
  exit 1
}
Write-Host 'La firma es la correcta.' -ForegroundColor Green
exit 0
