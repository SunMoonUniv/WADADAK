<#
운영 PC에서 매일 돈다. Taildrop으로 받은 덤프(Downloads)를 백업 폴더로 옮기고, $KeepDays일 지난 것을 지우고,
그날 core · run 덤프 중 빠진 것이 있으면 Discord로 알린다. 절차는 deploy/backup/README.md.
#>
[CmdletBinding()]
param(
    [string]$Inbox = (Join-Path $env:USERPROFILE 'Downloads'),
    [string]$Dir = 'C:\wadadak-backup',
    [ValidateRange(1, 365)][int]$KeepDays = 30,
    # Discord 웹훅은 감시 설정의 .env 한 곳에만 둔다.
    [string]$EnvFile = 'C:\wadadak-observability\ops\.env',
    [datetime]$Date = (Get-Date)
)

$ErrorActionPreference = 'Stop'
# Windows PowerShell 5.1은 TLS 1.2를 기본으로 켜지 않을 수 있다(healthchecks.io · Discord는 HTTPS).
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

function Send-Discord([string]$Text) {
    $line = Get-Content -LiteralPath $EnvFile | Where-Object { $_ -like 'DISCORD_WEBHOOK_URL=*' } | Select-Object -First 1
    if (-not $line) { throw "$EnvFile 에 DISCORD_WEBHOOK_URL이 없다" }
    $url = $line.Substring('DISCORD_WEBHOOK_URL='.Length).Trim().Trim("'", '"')
    $body = [Text.Encoding]::UTF8.GetBytes((@{ content = $Text } | ConvertTo-Json -Compress))
    Invoke-RestMethod -Method Post -Uri $url -ContentType 'application/json; charset=utf-8' -Body $body | Out-Null
}

foreach ($n in 'core', 'run') { New-Item -ItemType Directory -Force (Join-Path $Dir $n) | Out-Null }

Get-ChildItem -LiteralPath $Inbox -File | ForEach-Object {
    if ($_.Name -match '^(core|run)-\d{8}\.dump$') {
        Move-Item -Force -LiteralPath $_.FullName -Destination (Join-Path (Join-Path $Dir $Matches[1]) $_.Name)
    }
}

$cutoff = $Date.Date.AddDays(-$KeepDays)
Get-ChildItem -LiteralPath $Dir -Recurse -File -Filter *.dump | Where-Object {
    $_.BaseName -match '-(\d{8})$' -and [datetime]::ParseExact($Matches[1], 'yyyyMMdd', $null) -lt $cutoff
} | Remove-Item -Force

$day = '{0:yyyyMMdd}' -f $Date
$missing = @('core', 'run' | Where-Object { -not (Test-Path (Join-Path $Dir "$_\$_-$day.dump")) })
if ($missing.Count -gt 0) {
    Send-Discord ("⚠️ DB 백업이 오지 않았습니다: {0} ({1:yyyy-MM-dd})`n확인할 곳: 그 PC의 C:\wadadak-backup\backup.log, 작업 스케줄러 'WADADAK DB Backup'" -f ($missing -join ', '), $Date)
    exit 1
}
Write-Host "OK core-$day.dump, run-$day.dump"
