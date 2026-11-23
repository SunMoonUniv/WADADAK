[CmdletBinding()]
param(
    [PSCredential]$Credential,

    # Grafana 연락 지점(wadadak-discord)으로 시험 메시지를 한 번 보낸다.
    [switch]$SendTest,

    [string]$GrafanaUrl = 'http://127.0.0.1:3000'
)

# run PC에서 실행한다. Grafana API만 쓴다(Prometheus는 호스트 포트가 없어 Grafana 데이터 소스로 조회).
# Discord 웹훅 주소는 출력하지 않는다(Grafana도 [REDACTED]로만 돌려준다).
$ErrorActionPreference = 'Stop'
if (-not $Credential) {
    $Credential = Get-Credential -UserName 'admin' -Message 'run PC Grafana에 로그인합니다.'
}
if (-not $Credential) { throw 'Grafana 로그인 정보가 필요합니다.' }

$login = '{0}:{1}' -f $Credential.UserName, $Credential.GetNetworkCredential().Password
$headers = @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($login)) }

function Invoke-Grafana([string]$Path, [string]$Method = 'Get', $Body) {
    $request = @{
        Uri = $GrafanaUrl.TrimEnd('/') + $Path; Method = $Method; Headers = $headers
        UseBasicParsing = $true; TimeoutSec = 15; MaximumRedirection = 0
    }
    if ($null -ne $Body) {
        $request.Body = [Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Depth 10 -Compress))
        $request.ContentType = 'application/json; charset=utf-8'
    }
    $response = Invoke-WebRequest @request
    $text = [Text.Encoding]::UTF8.GetString($response.RawContentStream.ToArray())
    # PowerShell 5.1의 ConvertFrom-Json은 JSON 배열을 한 덩어리로 내보낸다. 변수에 담았다가 돌려줘야 원소별로 나온다.
    if ($text) { $parsed = $text | ConvertFrom-Json; return $parsed }
}

function Invoke-PromQuery([string]$Query) {
    $path = '/api/datasources/proxy/uid/wadadak-prometheus/api/v1/query?query=' + [Uri]::EscapeDataString($Query)
    $result = Invoke-Grafana $path
    if ($result.status -ne 'success') { throw "Prometheus 조회 실패: $Query" }
    return @($result.data.result)
}

$failed = 0
function Write-Check([bool]$Ok, [string]$Text) {
    if ($Ok) { Write-Host "PASS - $Text" } else { Write-Host "FAIL - $Text"; $script:failed++ }
}

# 1. Prometheus가 core PC 15692를 읽는가
try {
    $up = @(Invoke-PromQuery 'up{job="rabbitmq-dlq"}')
    $upValue = if ($up.Count -gt 0) { $up[0].value[1] } else { '(없음)' }
    Write-Check ($upValue -eq '1') ("Prometheus 수집 대상 100.75.79.15:15692 up = {0}" -f $upValue)
} catch {
    Write-Check $false ("Grafana에서 Prometheus 데이터 소스(wadadak-prometheus)를 조회하지 못함: {0}" -f $_.Exception.Message)
}

# 2. 두 DLQ의 메시지 수
try {
    $series = @(Invoke-PromQuery 'rabbitmq_detailed_queue_messages{job="rabbitmq-dlq"}')
    foreach ($queue in @('wadadak.core-service.dlq', 'wadadak.run-service.dlq')) {
        $item = $series | Where-Object { $_.metric.queue -eq $queue } | Select-Object -First 1
        if ($item) {
            Write-Check $true ("{0} 메시지 수 = {1} (vhost {2})" -f $queue, $item.value[1], $item.metric.vhost)
        } else {
            Write-Check $false ("{0} 지표가 없음" -f $queue)
        }
    }
} catch {
    Write-Check $false ("DLQ 지표 조회 실패: {0}" -f $_.Exception.Message)
}

# 2-1. 업무 큐 소비자 수 (queue_consumer_count 수집 확인. 0이면 '큐 소비자 없음' 알림 대상)
try {
    $consumers = @(Invoke-PromQuery 'rabbitmq_detailed_queue_consumers{job="rabbitmq-dlq"}')
    foreach ($queue in @('wadadak.core-service', 'wadadak.run-service')) {
        $item = $consumers | Where-Object { $_.metric.queue -eq $queue } | Select-Object -First 1
        if ($item) {
            Write-Check ([int]$item.value[1] -ge 1) ("{0} 소비자 수 = {1}" -f $queue, $item.value[1])
        } else {
            Write-Check $false ("{0} 소비자 지표가 없음 (prometheus.yml family에 queue_consumer_count가 있는지 확인)" -f $queue)
        }
    }
} catch {
    Write-Check $false ("소비자 지표 조회 실패: {0}" -f $_.Exception.Message)
}

# 3. 알림 규칙·연락 지점·대시보드가 provisioning으로 들어왔는가
$rules = @(Invoke-Grafana '/api/v1/provisioning/alert-rules')
foreach ($uid in @('wadadak-dlq-residual', 'wadadak-dlq-scrape-down', 'wadadak-dlq-series-missing', 'wadadak-queue-consumer-zero')) {
    $rule = $rules | Where-Object { $_.uid -eq $uid } | Select-Object -First 1
    Write-Check ([bool]$rule) ("알림 규칙 {0} {1}" -f $uid, $(if ($rule) { '(' + $rule.title + ')' } else { '없음' }))
}
$contactPoints = @(Invoke-Grafana '/api/v1/provisioning/contact-points')
$discord = $contactPoints | Where-Object { $_.uid -eq 'wadadak-discord' } | Select-Object -First 1
Write-Check ([bool]$discord -and $discord.type -eq 'discord') '연락 지점 wadadak-discord (Discord)'
try {
    $dashboard = Invoke-Grafana '/api/dashboards/uid/wadadak-rabbitmq-dlq'
    Write-Check $true ("대시보드 {0} (폴더 {1})" -f $dashboard.dashboard.title, $dashboard.meta.folderTitle)
} catch {
    Write-Check $false '대시보드 wadadak-rabbitmq-dlq 없음 (dashboards 폴더에 rabbitmq-dlq.json 복사 후 30초 대기)'
}

# 4. 지금 알림 상태(참고)
try {
    $groups = (Invoke-Grafana '/api/prometheus/grafana/api/v1/rules').data.groups | Where-Object { $_.name -eq 'rabbitmq-dlq' }
    foreach ($rule in @($groups.rules)) {
        $instances = @($rule.alerts | ForEach-Object {
            $label = if ($_.labels.queue) { $_.labels.queue } else { '-' }
            '{0}={1}' -f $label, $_.state
        }) -join ', '
        Write-Host ("INFO - [{0}] {1} / health={2} {3}" -f $rule.state, $rule.name, $rule.health, $instances)
    }
} catch {
    Write-Host ("INFO - 알림 상태 조회 실패: {0}" -f $_.Exception.Message)
}

# 5. 선택: Discord 시험 전송
if ($SendTest) {
    $receiverName = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('wadadak-discord')).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    $receiver = Invoke-Grafana "/apis/notifications.alerting.grafana.app/v1beta1/namespaces/default/receivers/$receiverName"
    $integration = $receiver.spec.integrations | Where-Object { $_.uid -eq 'wadadak-discord' } | Select-Object -First 1
    if (-not $integration) { throw '연락 지점 wadadak-discord를 찾지 못했습니다.' }
    $body = @{
        integration = $integration
        alert = @{
            labels = @{ alertname = 'DLQ 알림 연결 시험' }
            annotations = @{ summary = 'Grafana에서 Discord로 보내는 연결 시험입니다. 실제 DLQ 상태와 관계없습니다.' }
        }
    }
    $result = Invoke-Grafana "/apis/notifications.alerting.grafana.app/v1beta1/namespaces/default/receivers/$receiverName/test" 'Post' $body
    Write-Check ($result.status -eq 'success') ("Discord 시험 전송: Grafana 응답 {0}. Discord 채널에 '⚠️ DLQ 알림 연결 시험'이 왔는지 확인하세요." -f $result.status)
}

if ($failed -gt 0) { throw ("확인 실패 {0}건" -f $failed) }
Write-Host '모든 확인 통과'
