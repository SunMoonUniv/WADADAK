[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$compose = Join-Path $PSScriptRoot 'compose.yaml'
$marker = 'WADADAK_CORE_OBSERVABILITY_SMOKE ' + [Guid]::NewGuid().ToString('N')

$alloy = docker compose -p wadadak-core-observability -f $compose ps --status running -q alloy
if ($LASTEXITCODE -ne 0 -or -not $alloy) { throw 'The core Alloy container must be running.' }

$container = docker compose -p wadadak-core-observability -f $compose --profile smoke run --detach --rm --no-deps smoke sh -c 'echo "$1" && sleep 180' smoke $marker
if ($LASTEXITCODE -ne 0 -or -not $container) { throw 'Could not start the core smoke container.' }

for ($attempt = 0; $attempt -lt 10; $attempt++) {
    $lines = docker logs $container
    if ($LASTEXITCODE -eq 0 -and $lines -ccontains $marker) {
        Write-Output $marker
        return
    }
    Start-Sleep -Seconds 1
}
throw 'The core smoke container did not emit the expected marker.'
