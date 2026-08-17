# PreToolUse guard — bloquea operaciones destructivas o que tocan salda-prod
# antes de que se ejecuten. Recibe el payload del hook por stdin (JSON) y
# solo inspecciona texto: nunca ejecuta el comando que está evaluando.
$ErrorActionPreference = 'Stop'

try {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
    $data = $raw | ConvertFrom-Json
    $cmd = $data.tool_input.command
} catch {
    # Payload ilegible: no bloqueamos por un fallo nuestro, dejamos pasar.
    exit 0
}

if ([string]::IsNullOrWhiteSpace($cmd)) { exit 0 }

# ponytail: lista de patrones, no un parser de shell — cubre los casos
# pedidos; ampliar aquí si aparece una variante nueva que se cuele.
$patterns = @(
    @{ Pattern = 'salda-prod'; Reason = 'Referencia operativa a salda-prod (produccion). Cualquier comando que seleccione, modifique o despliegue produccion esta bloqueado hasta la ventana de promocion explicita.' }
    @{ Pattern = 'firebase(\.cmd|\.exe)?\s+.*\bdeploy\b'; Reason = 'firebase deploy bloqueado: no se despliega nada automaticamente.' }
    @{ Pattern = 'git\s+push\b.*(--force(-with-lease)?\b|(^|\s)-f(\s|$))'; Reason = 'git push --force / --force-with-lease / -f bloqueado.' }
    @{ Pattern = 'git\s+reset\b.*--hard\b'; Reason = 'git reset --hard bloqueado: descarta trabajo sin confirmar.' }
    @{ Pattern = 'git\s+clean\b.*-[a-zA-Z]*f'; Reason = 'git clean con -f (borrado forzado de no versionados) bloqueado.' }
    @{ Pattern = '(^|[;&|]|\s)rm\s+.*-[a-zA-Z]*r[a-zA-Z]*f|(^|[;&|]|\s)rm\s+.*-[a-zA-Z]*f[a-zA-Z]*r'; Reason = 'rm -rf (o combinacion recursiva+forzada) bloqueado.' }
    @{ Pattern = 'Remove-Item\b.*-Recurse\b.*-Force\b|Remove-Item\b.*-Force\b.*-Recurse\b'; Reason = 'Remove-Item recursivo y forzado bloqueado.' }
)

foreach ($p in $patterns) {
    if ($cmd -match $p.Pattern) {
        [Console]::Error.WriteLine("[SALDA safety hook] Comando BLOQUEADO: $($p.Reason)")
        [Console]::Error.WriteLine("Comando recibido: $cmd")
        exit 2
    }
}

exit 0
