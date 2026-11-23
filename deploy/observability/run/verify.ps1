[CmdletBinding()]
param(
    [string]$GrafanaUrl = 'http://127.0.0.1:3000',
    [PSCredential]$Credential
)

$ErrorActionPreference = 'Stop'

function Test-GrafanaLogs([string]$Query, [DateTimeOffset]$Since) {
    $start = "$($Since.ToUnixTimeMilliseconds())000000"
    $end = "$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())000000"
    $escapedQuery = [Uri]::EscapeDataString($Query)
    $response = Invoke-RestMethod -Uri "$queryEndpoint`?query=$escapedQuery&start=$start&end=$end&limit=1" -Headers $headers -TimeoutSec 10
    if ($response.status -ne 'success' -or $response.data.resultType -ne 'streams') {
        throw 'Grafana did not return a Loki log query result. Check the Loki data source and credentials.'
    }
    foreach ($stream in $response.data.result) {
        if ($stream.values.Count -gt 0) { return $true }
    }
    return $false
}

if (-not $Credential) {
    $Credential = Get-Credential -UserName 'admin' -Message 'Sign in to the run PC Grafana to verify log search.'
}
if (-not $Credential) { throw 'Grafana credentials are required.' }

$basicAuth = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($Credential.UserName):$($Credential.GetNetworkCredential().Password)"))
$headers = @{ Authorization = "Basic $basicAuth" }
$queryEndpoint = $GrafanaUrl.TrimEnd('/') + '/api/datasources/proxy/uid/wadadak-loki/loki/api/v1/query_range'

Push-Location -LiteralPath $PSScriptRoot
try {
    $since = [DateTimeOffset]::UtcNow.AddMinutes(-1)
    docker compose --profile smoke up -d --no-deps --force-recreate smoke
    if ($LASTEXITCODE -ne 0) { throw 'Could not start the smoke container.' }

    try {
        $deadline = [DateTimeOffset]::UtcNow.AddMinutes(2)
        $marker = $null
        $smokeFound = $false
        do {
            if (-not $marker) {
                $output = docker compose --profile smoke logs --no-log-prefix --tail 5 smoke
                if ($LASTEXITCODE -ne 0) { throw 'Could not read the smoke container log.' }
                $marker = $output | Where-Object { $_ -match '^WADADAK_OBSERVABILITY_SMOKE [0-9]{8}T[0-9]{6}Z$' } | Select-Object -Last 1
            }
            if ($marker) {
                $smokeFound = Test-GrafanaLogs ('{service="smoke"} |= "' + $marker + '"') $since
            }
            if (-not $smokeFound) { Start-Sleep -Seconds 5 }
        } until ($smokeFound -or [DateTimeOffset]::UtcNow -ge $deadline)

        if (-not $marker) { throw 'The smoke container did not emit a test log.' }
        if (-not $smokeFound) { throw "Grafana did not find this test log within two minutes: $marker" }
        Write-Host "PASS - Grafana found the new smoke log: $marker"

        if (-not (Test-GrafanaLogs '{service="run"}' ([DateTimeOffset]::UtcNow.AddDays(-7)))) {
            throw 'Grafana found the smoke log but no actual run log. Check the run target and its source logs from the last seven days.'
        }
        Write-Host 'PASS - Grafana found an actual run log from the last seven days.'
    } finally {
        docker compose --profile smoke rm --stop --force smoke
        if ($LASTEXITCODE -ne 0) { Write-Warning 'Could not remove the smoke container.' }
    }
} finally {
    Pop-Location
}
