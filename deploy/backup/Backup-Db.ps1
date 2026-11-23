<#
그 PC의 DB를 pg_dump(custom 형식)로 떠서 운영 PC로 Taildrop으로 보낸다. 절차는 deploy/backup/README.md.
  core PC: -Container wadadak-core-postgres-1 -DbUser wadadak     -Name core
  run PC : -Container wadadak-run-postgres-1  -DbUser wadadak_run -Name run
이 PC에는 최근 $Keep개만 남긴다. 결과는 $Dir\backup.log에 한 줄씩 남는다.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Container,
    [Parameter(Mandatory)][string]$DbUser,
    [Parameter(Mandatory)][ValidateSet('core', 'run')][string]$Name,
    [string]$Target = 'desktop-65isqe2',
    [string]$Dir = 'C:\wadadak-backup',
    [ValidateRange(1, 30)][int]$Keep = 3
)

$ErrorActionPreference = 'Stop'
# SSH 세션 · 작업 스케줄러에서 PATH에 없을 수 있어 전체 경로로 부른다.
$docker = 'C:\Program Files\Docker\Docker\resources\bin\docker.exe'
$tailscale = 'C:\Program Files\Tailscale\tailscale.exe'

New-Item -ItemType Directory -Force $Dir | Out-Null
$log = Join-Path $Dir 'backup.log'
function Write-Log([string]$Message) {
    Add-Content -Path $log -Value ('{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $Message) -Encoding UTF8
}

$file = Join-Path $Dir ('{0}-{1:yyyyMMdd}.dump' -f $Name, (Get-Date))
try {
    # 컨테이너 안의 pg_dump를 쓴다. 복원하는 쪽과 메이저 버전(17)이 같아야 한다.
    & $docker exec $Container pg_dump -U $DbUser -d wadadak -Fc -f /tmp/wadadak-backup.dump
    if ($LASTEXITCODE -ne 0) { throw "pg_dump 실패($LASTEXITCODE)" }
    & $docker cp "${Container}:/tmp/wadadak-backup.dump" $file
    if ($LASTEXITCODE -ne 0) { throw "docker cp 실패($LASTEXITCODE)" }
    & $docker exec $Container rm -f /tmp/wadadak-backup.dump | Out-Null
    # 덤프에는 회원 정보가 있다. 운영 PC 말고는 보내지 않는다.
    & $tailscale file cp $file "${Target}:"
    if ($LASTEXITCODE -ne 0) { throw "Taildrop 실패($LASTEXITCODE)" }
    Write-Log ('OK {0} {1} bytes' -f (Split-Path $file -Leaf), (Get-Item $file).Length)
} catch {
    Write-Log ('FAIL {0}: {1}' -f $Name, $_.Exception.Message)
    throw
}

Get-ChildItem $Dir -Filter "$Name-*.dump" | Sort-Object Name -Descending | Select-Object -Skip $Keep | Remove-Item -Force
