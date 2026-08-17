# PostToolUse (Write|Edit) — dos responsabilidades sobre el archivo tocado:
#  1) si es .dart, formatearlo con `dart format` (informa por stderr si falla).
#  2) si es codigo relevante de SALDA, apuntarlo en el marcador de
#     validacion pendiente que lee el Stop hook (stop-validate.ps1).
$ErrorActionPreference = 'Stop'

try {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
    $data = $raw | ConvertFrom-Json
    $path = $data.tool_input.file_path
    if ([string]::IsNullOrWhiteSpace($path)) { $path = $data.tool_response.filePath }
} catch {
    exit 0
}

if ([string]::IsNullOrWhiteSpace($path)) { exit 0 }
if (-not (Test-Path -LiteralPath $path)) { exit 0 }

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$fullPath = (Resolve-Path -LiteralPath $path).Path
$relPath = $fullPath.Substring($projectRoot.Length + 1) -replace '\\', '/'

# Codigo/config de Claude no cuenta como "codigo funcional de SALDA".
$isClaudeConfig = $relPath -match '^\.claude/' -or $relPath -match '^(docs/|CLAUDE\.md$|AGENTS\.md$|README\.md$)'

$formatError = $null
if ($relPath -match '\.dart$') {
    Push-Location $projectRoot
    $out = & dart format $relPath 2>&1
    $code = $LASTEXITCODE
    Pop-Location
    if ($code -ne 0) { $formatError = $out -join "`n" }
}

if (-not $isClaudeConfig -and ($relPath -match '\.(dart|ts|mjs|js|svelte)$' -or $relPath -match '\.rules$')) {
    $marker = Join-Path $projectRoot '.claude/.validation-pending'
    # ascii, no utf8: PS 5.1 antepone BOM a un archivo utf8 nuevo y eso
    # rompe el prefix-match ("-like") de la primera ruta en stop-validate.ps1.
    # Las rutas del repo son ASCII por convencion (identificadores en ingles).
    Add-Content -LiteralPath $marker -Value $relPath -Encoding ascii
}

if ($formatError) {
    [Console]::Error.WriteLine("[SALDA formatter] dart format fallo en $relPath`n$formatError")
    exit 2
}

exit 0
