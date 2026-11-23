<#
운영 PC에서 매주 돈다. 가장 최근 core · run 덤프를 임시 컨테이너에 복원해 본다.
오류가 나거나 복원된 테이블 수가 덤프 목록과 다르면 Discord로 알린다. 절차는 deploy/backup/README.md.
사진은 core 덤프와 같은 날짜 tar를 열어, 복원한 core DB가 가리키는 사진이 모두 들어 있는지 본다.
.env에 HEALTHCHECKS_RESTORE_URL이 있으면 성공하면 핑, 실패하면 /fail을 보낸다. 작업이 아예 안 돈 주는 healthchecks.io가 알린다.
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

# Windows PowerShell 5.1은 TLS 1.2를 기본으로 켜지 않을 수 있다(healthchecks.io · Discord는 HTTPS).
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
function Get-EnvValue([string]$Key) {
    $line = Get-Content -LiteralPath $EnvFile | Where-Object { $_ -like "$Key=*" } | Select-Object -First 1
    if ($line) { $line.Substring($Key.Length + 1).Trim().Trim("'", '"') }
}

# healthchecks.io 핑(.env에 주소가 있을 때만). 핑이 실패해도 결과는 바꾸지 않는다.
function Send-Ping([string]$Suffix) {
    $url = Get-EnvValue 'HEALTHCHECKS_RESTORE_URL'
    if (-not $url) { return }
    try { Invoke-WebRequest -Uri ($url + $Suffix) -UseBasicParsing -TimeoutSec 10 | Out-Null } catch { Write-Warning "ping: $($_.Exception.Message)" }
}

function Send-Discord([string]$Text) {
    $url = Get-EnvValue 'DISCORD_WEBHOOK_URL'
    if (-not $url) { throw "$EnvFile 에 DISCORD_WEBHOOK_URL이 없다" }
    $body = [Text.Encoding]::UTF8.GetBytes((@{ content = $Text } | ConvertTo-Json -Compress))
    Invoke-RestMethod -Method Post -Uri $url -ContentType 'application/json; charset=utf-8' -Body $body | Out-Null
}

# 확장(PostGIS 등)이 만든 표는 덤프 목록에 없으므로 뺀다.
$countTables = "select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace " +
    "where c.relkind in ('r', 'p') and n.nspname not in ('pg_catalog', 'information_schema') and n.nspname not like 'pg_toast%' " +
    "and not exists (select 1 from pg_depend d where d.classid = 'pg_class'::regclass and d.objid = c.oid and d.deptype = 'e')"
# 리뷰 · 프로필 사진 키(DB 구조.md). 저장하지 않은 업로드(common.photo_uploads)는 1시간 뒤 지워지니 보지 않는다.
$photoKeysSql = 'select photo_key from review.review_photos union all select profile_image_key from member.members where profile_image_key is not null'

$problems = @()
$photoKeys = $null
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
        if ($n -eq 'core') {
            $keys = @(& $docker exec $container psql -U postgres -d wadadak -Atc $photoKeysSql)
            if ($LASTEXITCODE -ne 0) { throw "사진 키를 읽지 못했다($LASTEXITCODE)" }
            $photoKeys = $keys
            $photoTar = Join-Path $Dir ('photos\photos-{0}.tar' -f $file.BaseName.Substring('core-'.Length))
        }
    } catch {
        $problems += "$n ($($file.Name)): $($_.Exception.Message)"
    } finally {
        & $docker rm -f $container 2>$null | Out-Null
    }
}

# 사진은 core 덤프보다 늦게 뜬다(04:00 → 04:10). 같은 날짜 tar에 그 덤프가 가리키는 사진이 모두 있어야 한다.
# RustFS는 객체 하나를 <버킷>/<키>/xl.meta 폴더로 둔다. core 복원이 실패했으면 키가 없어 건너뛴다.
if ($null -ne $photoKeys) {
    try {
        if (-not (Test-Path -LiteralPath $photoTar)) { throw '같은 날짜 사진 tar가 없다' }
        $entries = @(& "$env:SystemRoot\System32\tar.exe" -tf $photoTar)
        if ($LASTEXITCODE -ne 0) { throw "tar를 읽지 못했다($LASTEXITCODE)" }
        $inTar = [Collections.Generic.HashSet[string]]::new([string[]]$entries)
        $lost = @($photoKeys | Where-Object { -not $inTar.Contains("./wadadak/$_/xl.meta") })
        if ($lost.Count -gt 0) { throw "사진 $($lost.Count)장이 없다: $(($lost | Select-Object -First 5) -join ', ')" }
        Write-Host "OK $(Split-Path $photoTar -Leaf) photos=$($photoKeys.Count)"
    } catch {
        $problems += "photos ($(Split-Path $photoTar -Leaf)): $($_.Exception.Message)"
    }
}

if ($problems.Count -gt 0) {
    Send-Ping '/fail'
    Send-Discord ("⚠️ 백업 복원 검사 실패`n" + ($problems -join "`n"))
    exit 1
}
Send-Ping ''
