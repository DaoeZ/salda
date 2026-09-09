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

# Excepcion ACOTADA (autorizada por el usuario): publicar en DESARROLLO las
# reglas e indices de Firestore, las Functions o las reglas de Storage. Es la
# unica forma de que la autoridad del backend llegue al proyecto donde se
# prueba, y NO abre hosting ni produccion.
#
# Se valida por TOKENS, no por substring: cualquier bandera desconocida, un
# objetivo fuera de la lista, otro proyecto, o un intento de
# encadenar/redirigir/sustituir comandos, invalida la excepcion y el comando
# vuelve a estar bloqueado. Mas vale rechazar una variante legitima que
# aceptar una que no lo sea.
#
# `functions` y `storage` solo se admiten como objetivo UNICO: mezclarlos con
# otros amplia el alcance de un despliegue que se pidio acotado, y nada obliga
# a hacerlo en la misma orden.
function Test-AllowedFirestoreDeploy([string]$command) {
    # Un unico comando: nada de `;`, `&&`, tuberias, redirecciones ni `$(...)`.
    if ($command -match '[;&|`$><]') { return $false }

    $tokens = @($command -split '\s+' | Where-Object { $_ -ne '' })
    if ($tokens.Count -lt 2) { return $false }
    if ($tokens[0] -notmatch '^firebase(\.cmd|\.exe)?$') { return $false }
    if ($tokens[1] -ne 'deploy') { return $false }

    $firestoreTargets = @('firestore:rules', 'firestore:indexes')
    $allowedProjects = @('dev', 'salda-dev')
    $sawOnly = $false
    $sawProject = $false

    for ($i = 2; $i -lt $tokens.Count; $i++) {
        if ($tokens[$i] -eq '--only') {
            if ($i + 1 -ge $tokens.Count) { return $false }
            $i++
            $targets = @($tokens[$i] -split ',' | Where-Object { $_ -ne '' })
            if ($targets.Count -eq 0) { return $false }
            # Tres combinaciones, y ninguna se mezcla con otra: reglas e
            # indices de Firestore juntos, Functions a solas, o Storage a
            # solas. Storage se abre en A11b: la foto del ticket es la
            # evidencia del gasto y su politica vive en storage.rules, asi
            # que sin publicarla la autoridad queda a medias en desarrollo.
            #
            # Comparacion SENSIBLE a mayusculas (`-ccontains`): `-contains` no
            # lo es, y colaba `--only STORAGE`. La excepcion tiene que
            # reconocer exactamente la orden que se autorizo, no una variante
            # parecida.
            $objetivosUnicos = @('functions', 'storage')
            $esObjetivoUnico = $targets.Count -eq 1 `
                -and $objetivosUnicos -ccontains $targets[0]
            if (-not $esObjetivoUnico) {
                foreach ($target in $targets) {
                    if ($firestoreTargets -cnotcontains $target) { return $false }
                }
            }
            $sawOnly = $true
        }
        elseif ($tokens[$i] -eq '--project') {
            if ($i + 1 -ge $tokens.Count) { return $false }
            $i++
            if ($allowedProjects -cnotcontains $tokens[$i]) { return $false }
            $sawProject = $true
        }
        else {
            # Cualquier otra bandera (--force, --token, -P...) invalida.
            return $false
        }
    }

    # Sin --only se desplegaria TODO; sin --project, al alias por defecto.
    return $sawOnly -and $sawProject
}

$allowedDeploy = Test-AllowedFirestoreDeploy $cmd

# ponytail: lista de patrones, no un parser de shell — cubre los casos
# pedidos; ampliar aquí si aparece una variante nueva que se cuele.
$patterns = @(
    @{ Pattern = 'salda-prod'; Reason = 'Referencia operativa a salda-prod (produccion). Cualquier comando que seleccione, modifique o despliegue produccion esta bloqueado hasta la ventana de promocion explicita.' }
    @{ Name = 'firebase-deploy'; Pattern = 'firebase(\.cmd|\.exe)?\s+.*\bdeploy\b'; Reason = 'firebase deploy bloqueado: solo se admite `firebase deploy --only firestore:rules[,firestore:indexes] --project dev`, `--only functions --project dev` o `--only storage --project dev`.' }
    @{ Pattern = 'git\s+push\b.*(--force(-with-lease)?\b|(^|\s)-f(\s|$))'; Reason = 'git push --force / --force-with-lease / -f bloqueado.' }
    @{ Pattern = 'git\s+reset\b.*--hard\b'; Reason = 'git reset --hard bloqueado: descarta trabajo sin confirmar.' }
    @{ Pattern = 'git\s+clean\b.*-[a-zA-Z]*f'; Reason = 'git clean con -f (borrado forzado de no versionados) bloqueado.' }
    @{ Pattern = '(^|[;&|]|\s)rm\s+.*-[a-zA-Z]*r[a-zA-Z]*f|(^|[;&|]|\s)rm\s+.*-[a-zA-Z]*f[a-zA-Z]*r'; Reason = 'rm -rf (o combinacion recursiva+forzada) bloqueado.' }
    @{ Pattern = 'Remove-Item\b.*-Recurse\b.*-Force\b|Remove-Item\b.*-Force\b.*-Recurse\b'; Reason = 'Remove-Item recursivo y forzado bloqueado.' }
)

foreach ($p in $patterns) {
    # La excepcion solo levanta el veto del DEPLOY. El resto de patrones
    # —salda-prod incluido— se siguen aplicando sobre el mismo comando.
    if ($p.Name -eq 'firebase-deploy' -and $allowedDeploy) { continue }
    if ($cmd -match $p.Pattern) {
        [Console]::Error.WriteLine("[SALDA safety hook] Comando BLOQUEADO: $($p.Reason)")
        [Console]::Error.WriteLine("Comando recibido: $cmd")
        exit 2
    }
}

exit 0
