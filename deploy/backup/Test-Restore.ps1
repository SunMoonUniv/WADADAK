<#
운영 PC에서 매주 돈다. 가장 최근 core · run 덤프를 임시 컨테이너에 복원해 본다.
오류가 나거나 복원된 테이블 수가 덤프 목록과 다르면 Discord로 알린다. 절차는 deploy/backup/README.md.
#>
[CmdletBinding()]
param(
    [string]$Dir = 'C:\wadadak-backup',
    [string]$EnvFile = 'C:\wadadak-observability\ops\.env',
    # 서버와 같은 메이저(17). core 덤프에 PostGIS가 있어 postgis 이미지로 둘 다 복원한다.
    [string]$Image = 'postgis/postgis:17-3.5'
)

$ErrorActionPreference = 'Stop'
$docker = 'C:\Program Files\Docker\Docker\resources\bin\docker.exe'
$container = 'wadadak-restore-test'

function Send-Discord([string]$Text) {
    $line = Get-Content -LiteralPath $EnvFile | Where-Object { $_ -like 'DISCORD_WEBHOOK_URL=*' } | Select-Object -First 1
    if (-not $line) { throw "$EnvFile 에 DISCORD_WEBHOOK_URL이 없다" }
    $url = $line.Substring('DISCORD_WEBHOOK_URL='.Length).Trim().Trim("'", '"')
    $body = [Text.Encoding]::UTF8.GetBytes((@{ content = $Text } | ConvertTo-Json -Compress))
    Invoke-RestMethod -Method Post -Uri $url -ContentType 'application/json; charset=utf-8' -Body $body | Out-Null
}

# 확장(PostGIS 등)이 만든 표는 덤프 목록에 없으므로 뺀다.
$countTables = "select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace " +
    "where c.relkind in ('r', 'p') and n.nspname not in ('pg_catalog', 'information_schema') and n.nspname not like 'pg_toast%' " +
    "and not exists (select 1 from pg_depend d where d.classid = 'pg_class'::regclass and d.objid = c.oid and d.deptype = 'e')"

$problems = @()
foreach ($n in 'core', 'run') {
    $file = Get-ChildItem -LiteralPath (Join-Path $Dir $n) -Filter "$n-*.dump" -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
    if (-not $file) { $problems += "${n}: 덤프가 없다"; continue }
    & $docker rm -f $container 2>$null | Out-Null
    try {
        & $docker run -d --name $container -e POSTGRES_PASSWORD=restore-test -v "$($file.DirectoryName):/backup:ro" $Image | Out-Null
        if ($LASTEXITCODE -ne 0) { throw '임시 컨테이너를 띄우지 못했다' }
        # 초기화 중의 임시 서버는 TCP를 열지 않는다. TCP로 붙으면 초기화가 끝난 것이다.
        $ready = $false
        for ($i = 0; $i -lt 60 -and -not $ready; $i++) {
            Start-Sleep -Seconds 2
            & $docker exec $container pg_isready -h 127.0.0.1 -U postgres -q
            $ready = ($LASTEXITCODE -eq 0)
        }
        if (-not $ready) { throw 'DB가 뜨지 않았다' }
        # 목록 줄: "<번호>; <oid> <oid> TABLE <스키마> <이름> <소유자>". TABLE DATA 줄은 뺀다.
        # Windows PowerShell 5.1은 외부 명령 인자 안의 큰따옴표를 망가뜨려 큰따옴표 없이 쓴다.
        $expected = (& $docker exec $container sh -c "pg_restore -l '/backup/$($file.Name)' | awk '`$4 ~ /^TABLE`$/ && `$5 !~ /^DATA`$/' | wc -l").Trim()
        & $docker exec $container createdb -U postgres -T template0 wadadak
        if ($LASTEXITCODE -ne 0) { throw 'createdb 실패' }
        & $docker exec $container pg_restore -U postgres -d wadadak --no-owner --no-acl --exit-on-error "/backup/$($file.Name)"
        if ($LASTEXITCODE -ne 0) { throw "pg_restore 실패($LASTEXITCODE)" }
        $restored = (& $docker exec $container psql -U postgres -d wadadak -Atc $countTables).Trim()
        if ($restored -ne $expected) { throw "테이블 수가 다르다(덤프 $expected, 복원 $restored)" }
        Write-Host "OK $($file.Name) tables=$restored"
    } catch {
        $problems += "$n ($($file.Name)): $($_.Exception.Message)"
    } finally {
        & $docker rm -f $container 2>$null | Out-Null
    }
}

if ($problems.Count -gt 0) {
    Send-Discord ("⚠️ DB 백업 복원 검사 실패`n" + ($problems -join "`n"))
    exit 1
}
