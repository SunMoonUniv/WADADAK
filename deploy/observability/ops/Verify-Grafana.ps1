[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('\AWADADAK_CORE_OBSERVABILITY_SMOKE [0-9a-f]{32}\z')]
    [string]$SmokeMarker,

    [PSCredential]$Credential,

    [string]$GrafanaUrl = 'http://100.111.111.92:3000',

    # On the first import, an old one-line stream (e.g. the core startup line) stays in Loki
    # memory, where old timestamps are not searchable. It becomes searchable after the
    # 30-minute idle flush, so allow time for it on the first run.
    [ValidateRange(1, 60)]
    [int]$WaitMinutes = 20
)

$ErrorActionPreference = 'Stop'
if (-not $Credential) {
    $Credential = Get-Credential -UserName 'admin' -Message 'Sign in to the ops PC Grafana.'
}
if (-not $Credential) { throw 'Grafana credentials are required.' }

$login = '{0}:{1}' -f $Credential.UserName, $Credential.GetNetworkCredential().Password
$headers = @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($login)) }
$queryEndpoint = "$GrafanaUrl/api/datasources/proxy/uid/wadadak-loki/loki/api/v1/query_range"

function Find-GrafanaLog([string]$Query, [DateTimeOffset]$Since, [string]$ExpectedLine) {
    $start = "$($Since.ToUnixTimeMilliseconds())000000"
    $end = "$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())000000"
    $encoded = [Uri]::EscapeDataString($Query)
    $uri = "${queryEndpoint}?query=$encoded&start=$start&end=$end&limit=20"
    $response = Invoke-RestMethod -Uri $uri -Headers $headers -TimeoutSec 10 -MaximumRedirection 0
    if ($response.status -ne 'success' -or $response.data.resultType -ne 'streams') {
        throw 'Grafana did not return a successful Loki streams response.'
    }

    foreach ($stream in $response.data.result) {
        foreach ($entry in $stream.values) {
            if (-not $ExpectedLine -or $entry[1] -ceq $ExpectedLine) {
                return [DateTimeOffset]::FromUnixTimeMilliseconds([long]$entry[0].Substring(0, 13))
            }
        }
    }
    return $null
}

$now = [DateTimeOffset]::UtcNow
$checks = @(
    @{ Name = 'New core smoke'; Query = '{host="core-pc",service="smoke"} |= "' + $SmokeMarker + '"'; Since = $now.AddHours(-6); Expected = $SmokeMarker; Found = $null },
    @{ Name = 'Actual core log'; Query = '{host="core-pc",service="core"}'; Since = $now.AddDays(-7); Found = $null },
    @{ Name = 'Existing run log'; Query = '{service="run"}'; Since = $now.AddDays(-7); Found = $null }
)

$deadline = $now.AddMinutes($WaitMinutes)
$nextNotice = $now
do {
    foreach ($check in $checks) {
        if (-not $check.Found) {
            $check.Found = Find-GrafanaLog -Query $check.Query -Since $check.Since -ExpectedLine $check.Expected
            if ($check.Found) { Write-Host ('PASS - {0} ({1:yyyy-MM-dd HH:mm:ss} UTC)' -f $check.Name, $check.Found) }
        }
    }
    $pending = @($checks | Where-Object { -not $_.Found })
    if ($pending.Count -gt 0) {
        if ([DateTimeOffset]::UtcNow -ge $nextNotice) {
            Write-Host ('Waiting for: {0} (gives up at {1:HH:mm} UTC)' -f (($pending | ForEach-Object { $_.Name }) -join ', '), $deadline)
            $nextNotice = [DateTimeOffset]::UtcNow.AddMinutes(1)
        }
        Start-Sleep -Seconds 15
    }
} until ($pending.Count -eq 0 -or [DateTimeOffset]::UtcNow -ge $deadline)

foreach ($check in $pending) { Write-Host ('FAIL - {0}' -f $check.Name) }
if ($pending.Count -gt 0) { throw 'Grafana verification is incomplete.' }
