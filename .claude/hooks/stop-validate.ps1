# Stop hook — valida antes de dejar terminar una tarea, SOLO si hubo
# ediciones de codigo relevante (marcadas por posttooluse-write-edit.ps1).
# Usa exclusivamente los comandos verificados en la Fase 1 (los mismos que
# ejecuta .github/workflows/ci.yml).
#
# FAIL CLOSED en los tres casos: fallo de una validacion, tooling requerido
# ausente, o excepcion interna inesperada del propio hook -> siempre exit 2
# y el marcador SIEMPRE queda intacto. Nunca se borra salvo que todas las
# validaciones aplicables hayan terminado satisfactoriamente. Un hook de
# validacion roto no es motivo para dejar pasar: es motivo para investigar
# el hook (mensaje distinto para ese caso, ver el catch mas abajo). No hay
# recursion ni reintento dentro de este script: cada invocacion es una
# pasada unica; si sigue habiendo marcador, el propio Stop hook se volvera
# a invocar la proxima vez que Claude intente terminar, no antes.
$ErrorActionPreference = 'Continue'

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$marker = Join-Path $projectRoot '.claude/.validation-pending'

if (-not (Test-Path -LiteralPath $marker)) { exit 0 }

$touched = Get-Content -LiteralPath $marker | Where-Object { $_.Trim() -ne '' } | Select-Object -Unique
if (-not $touched) {
    Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
    exit 0
}

function Test-Touched([string]$prefix) {
    return [bool]($touched | Where-Object { $_ -like "$prefix*" })
}

# Ejecuta un comando de validacion en $WorkDir. Si $Tool no esta en PATH,
# NO se degrada a warning: cuenta como fallo bloqueante, porque una
# validacion obligatoria que no puede arrancar no es una validacion pasada.
function Invoke-Check {
    param(
        [Parameter(Mandatory)][string]$Tool,
        [Parameter(Mandatory)][string]$WorkDir,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][scriptblock]$Command
    )
    if (-not (Get-Command $Tool -ErrorAction SilentlyContinue)) {
        return "$Label : BLOQUEADO -- '$Tool' no esta disponible en PATH de este proceso. " +
               "Esta validacion es obligatoria (la ejecuta la CI) y no puede saltarse por un hueco de entorno: " +
               "instala/expon '$Tool' y reintenta antes de dar la tarea por terminada."
    }
    Push-Location $WorkDir
    try {
        $out = & $Command 2>&1
        if ($LASTEXITCODE -ne 0) {
            return "$Label`:`n$($out -join "`n")"
        }
        return $null
    } finally {
        Pop-Location
    }
}

$errors = @()

try {
    # 1) Analisis estatico del workspace completo (dart analyze, NO dart
    #    test) si se toco algun paquete Dart o la app.
    if (Test-Touched 'packages/' -or Test-Touched 'apps/mobile/') {
        $e = Invoke-Check -Tool 'dart' -WorkDir $projectRoot -Label 'dart analyze --fatal-infos' `
            -Command { dart analyze --fatal-infos }
        if ($e) { $errors += $e }
    }

    # 2) dart test SOLO dentro de cada package Dart puro tocado. Nunca en
    #    apps/mobile (esa app se valida con `flutter test`, paso 3).
    foreach ($pkg in @('packages/domain', 'packages/ocr_parser', 'packages/ai_providers', 'packages/design_tokens')) {
        $pkgPath = Join-Path $projectRoot $pkg
        if ((Test-Touched "$pkg/") -and (Test-Path (Join-Path $pkgPath 'test'))) {
            $e = Invoke-Check -Tool 'dart' -WorkDir $pkgPath -Label "dart test ($pkg)" `
                -Command { dart test }
            if ($e) { $errors += $e }
        }
    }

    # 3) flutter test en apps/mobile: si se toco la app directamente, o si
    #    se toco cualquier packages/* del que mobile depende (un cambio ahi
    #    puede romper la app aunque su propio `dart test` haya pasado).
    if (Test-Touched 'apps/mobile/' -or Test-Touched 'packages/') {
        $e = Invoke-Check -Tool 'flutter' -WorkDir (Join-Path $projectRoot 'apps/mobile') -Label 'flutter test (apps/mobile)' `
            -Command { flutter test }
        if ($e) { $errors += $e }
    }

    # 4) Cloud Functions (TS) si se tocaron.
    if (Test-Touched 'backend/functions/') {
        $e = Invoke-Check -Tool 'npm' -WorkDir (Join-Path $projectRoot 'backend/functions') -Label 'npm test (backend/functions)' `
            -Command { npm test }
        if ($e) { $errors += $e }
    }

    # 5) Reglas de Firestore si se tocaron: mismo comando que la CI
    #    (firebase emulators:exec). Si falta el CLI, BLOQUEA (no es opcional).
    if (Test-Touched 'backend/firestore/') {
        $e = Invoke-Check -Tool 'firebase' -WorkDir $projectRoot -Label 'reglas de Firestore (emulador)' `
            -Command { firebase emulators:exec --only firestore,storage --project demo-salda "npm --prefix backend/firestore test" }
        if ($e) { $errors += $e }
    }

    # 6) Web de invitados si se toco: las 4 validaciones obligatorias de la
    #    CI (job "guest-web" en ci.yml, ninguna con continue-on-error).
    if (Test-Touched 'apps/guest_web/') {
        $webDir = Join-Path $projectRoot 'apps/guest_web'
        $e = Invoke-Check -Tool 'npm' -WorkDir $webDir -Label 'npm run check (guest_web)' -Command { npm run check }
        if ($e) { $errors += $e }
        $e = Invoke-Check -Tool 'npm' -WorkDir $webDir -Label 'npm test (guest_web)' -Command { npm test }
        if ($e) { $errors += $e }
        $e = Invoke-Check -Tool 'npm' -WorkDir $webDir -Label 'npm run build (guest_web)' -Command { npm run build }
        if ($e) { $errors += $e }
        $e = Invoke-Check -Tool 'npm' -WorkDir $webDir -Label 'npm run check:size (guest_web)' -Command { npm run check:size }
        if ($e) { $errors += $e }
    }
} catch {
    # Excepcion interna inesperada del propio hook: NO es un fallo del
    # codigo de SALDA, es la infraestructura de validacion la que esta
    # rota. Fail closed igual que cualquier otro fallo: exit 2, marcador
    # intacto (no se borra), y un prefijo distinto para que Claude sepa
    # que debe investigar/corregir el hook, no el codigo de la app.
    [Console]::Error.WriteLine("SALDA VALIDATION INFRASTRUCTURE ERROR: excepcion interna en stop-validate.ps1, no relacionada con el codigo de SALDA. Antes de reintentar terminar la tarea, revisa y corrige el hook (.claude/hooks/stop-validate.ps1).")
    [Console]::Error.WriteLine("Detalle: $($_.Exception.Message)")
    [Console]::Error.WriteLine("En: $($_.InvocationInfo.PositionMessage)")
    exit 2
}

if ($errors.Count -gt 0) {
    [Console]::Error.WriteLine("[SALDA Stop hook] Validacion pendiente fallida. No se puede dar la tarea por terminada:`n")
    [Console]::Error.WriteLine(($errors -join "`n`n---`n`n"))
    exit 2
}

Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
exit 0
