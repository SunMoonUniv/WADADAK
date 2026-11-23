# run PC에서 할 일 (core 로그 수집 · RabbitMQ DLQ 감시)

core PC에서 원격으로 run PC를 조작할 수 없으므로 아래는 run PC 앞에서 직접 실행한다.
작업 폴더는 기존 모니터링 폴더 `C:\Users\301B-00\Desktop\observability`이다.
1~5번은 core 로그 수집(2026-11-20 완료), 6번은 RabbitMQ DLQ 감시다.

## 0. 파일 복사

4단계 전에 `Verify-Grafana.ps1`만 run PC 작업 폴더에 복사한다(USB·메신저 등 편한 방법).
Grafana에서 core smoke·실제 core·기존 run 로그를 각각 조회하는 스크립트다.
`compose.loki-tailnet.yaml`은 1단계 명령이 직접 만들기 때문에 복사하지 않아도 된다.

## 1. Loki 3100을 Tailscale IP에 열기

파일을 복사하지 않아도 된다. 아래 명령이 `compose.loki-tailnet.yaml`을 직접 만들고 Loki에 적용한다.
메신저 등을 거치면 백틱(`` ` ``)이 사라져 명령이 깨지므로 백틱 없는 명령만 쓴다. 한 줄씩 실행한다.

```powershell
cd C:\Users\301B-00\Desktop\observability
tailscale ip -4
```

위 결과가 `100.73.249.33`이 아니면 여기서 멈추고 나온 IP를 알려 준다(override 파일의 IP를 바꿔야 함).

```powershell
Set-Content -Path .\compose.loki-tailnet.yaml -Encoding ascii -Value 'services:','  loki:','    ports:','      - "100.73.249.33:3100:3100/tcp"'
docker compose -f .\compose.yaml -f .\compose.loki-tailnet.yaml up -d --no-deps loki
docker compose -f .\compose.yaml -f .\compose.loki-tailnet.yaml ps loki
```

- Loki가 뜨지 않으면(`cannot assign requested address` 등) `docker compose -f .\compose.yaml up -d --no-deps loki`로 원래대로 되돌린다.
- 마지막 명령의 PORTS에 `100.73.249.33:3100->3100/tcp`가 보여야 한다.
- Loki 컨테이너만 다시 만들어진다(약 15초 중단). run·Grafana·Alloy는 그대로다.
  Loki 데이터와 WAL은 `loki-data` 볼륨(`/loki`)에 있어 유지된다.

## 2. 이후 `docker compose up`에서도 포트가 유지되게 하기

`.env`에 한 줄을 추가한다. 이걸 안 하면 다음에 README대로 `docker compose up -d --force-recreate loki grafana`를
실행할 때 3100이 다시 닫히고 core 로그 전송이 끊긴다.

```powershell
if (-not (Select-String -Path .env -Pattern '^COMPOSE_FILE=' -Quiet)) { Add-Content -Path .env -Encoding ascii -Value '', 'COMPOSE_FILE=compose.yaml;compose.loki-tailnet.yaml' }
docker compose ps loki
```

(먼저 빈 값 `''`을 쓰는 건 기존 마지막 줄 뒤에 바로 붙어 비밀번호 줄이 망가지는 걸 막기 위해서다. 두 번 실행해도 한 번만 추가된다.)

## 3. 접근 제한 (Tailscale)

tailnet(`bbabbico.github`)에는 서버 PC 셋(인프라 · core · run)만 있다. 3100에 닿아야 하는 기기는 Alloy가 도는 인프라 PC와 core PC다.
팀원 기기를 tailnet에 추가하기 전에 Tailscale 관리 콘솔(Access controls)에서 정책을 바꾼다.
Tailscale ACL은 허용 규칙만 있으므로 "3100만 막기"가 아니라 허용할 것만 나열해야 한다. 기존 정책과 합쳐서 쓰고,
아래는 예시다.

```jsonc
{
  "hosts": {
    "infra-pc": "100.75.79.15",
    "core-pc":  "100.64.78.38",
    "run-pc":   "100.73.249.33"
  },
  "acls": [
    // 서버 PC 셋 사이: gateway → core · run, core · run → 브로커 · 저장소, run → core 내부 API, Alloy → Loki 3100 포함 전부 허용
    { "action": "accept", "src": ["infra-pc", "core-pc", "run-pc"], "dst": ["infra-pc:*", "core-pc:*", "run-pc:*"] }
    // 팀원 기기를 추가할 때는 필요한 포트만 따로 허용한다. 예: Grafana를 열려면 "run-pc:3000".
    // run-pc:3100(Loki)은 서버 PC 말고는 허용하지 않는다.
  ]
}
```

이 정책은 기본 "모두 허용" 정책을 대체하므로, 지금 두 PC 말고 tailnet을 쓰는 기기가 있다면 그 접근도 함께 적어야 한다.

## 4. Grafana 검증 (core PC에서 smoke 마커를 받은 뒤)

```powershell
cd C:\Users\301B-00\Desktop\observability
powershell -NoProfile -ExecutionPolicy Bypass -File .\Verify-Grafana.ps1 -SmokeMarker 'WADADAK_CORE_OBSERVABILITY_SMOKE <32자리>'
```

- Grafana `admin` 비밀번호(.env의 값)를 묻는다.
- `PASS` 3줄(New core smoke / Actual core log / Existing run log)이 나오면 완료.
- 기본 20분 기다린다(`-WaitMinutes`로 최대 60분). core Alloy를 처음 띄운 직후에는 core 기동 로그처럼
  한 줄짜리 옛 로그가 Loki 메모리에 남아 조회되지 않는다. 30분 idle flush 뒤,
  즉 Alloy 최초 기동 후 약 30분부터 조회된다. 한 번 올라간 뒤에는 바로 PASS가 나온다.
  `Waiting for: ...`가 나와도 기다리면 된다.
- 결과 전체를 core PC 작업자에게 보내 준다.

## 5. core 로그 대시보드 추가

`run/dashboards/core-logs.json`을 **파일 그대로** run PC의 `C:\Users\301B-00\Desktop\observability\dashboards\`에 복사한다.
Grafana가 30초 안에 자동으로 읽는다. 재시작은 필요 없다.

```powershell
cd C:\Users\301B-00\Desktop\observability
Test-Path .\dashboards\core-logs.json
```

`True`가 나오고 30초쯤 지나면 Grafana → Dashboards → Wadadak → **와다닥 core 서버 로그**가 보인다.
안 보이면 `docker compose logs --tail 30 grafana`에서 provisioning 오류를 확인한다.

| 패널 | 내용 |
| --- | --- |
| 오류 로그 수 | Spring ERROR, Caddy error/fatal/panic, RabbitMQ error 이상, cloudflared ERR/FTL을 서비스별 막대로 |
| 경고 로그 수 | core 와다닥 코드 WARN, Caddy warn, RabbitMQ warning, cloudflared WRN을 서비스별 막대로 |
| 서비스 기동 기록 (배포·재시작) | core 기동, RabbitMQ 기동 완료, Caddy 설정 적용 시점 |
| core PC 전체 요약 로그 | 수집한 요약 줄 전체(smoke 제외), 줄 앞에 `[서비스]` 표시 |

기본 기간은 최근 7일이다. 서비스 색은 core 파랑, gateway 보라, rabbitmq 주황, cloudflared 노랑으로 고정했다.
로그 패널의 `UNK`는 요약 줄에 level 정보가 없다는 뜻이다(정상).

## Explore에서 직접 조회

Grafana에서 직접 볼 때는 Explore → Loki → Code에서 기간을 Last 7 days로 두고 아래를 각각 실행한다.

```logql
{host="core-pc"}
{host="core-pc", service="core"}
{service="run"}
```

## 6. RabbitMQ DLQ 감시 (Prometheus · Grafana 알림 · Discord)

**먼저 할 일:** WADADAK PR #258(core PC RabbitMQ 15692를 `100.75.79.15`에 여는 변경)이 머지되고 배포가 끝나야 한다.
그 전에 적용하면 Prometheus가 15692를 못 읽어 Discord에 "DLQ 지표 수집 중단" 알림이 4시간마다 간다.
배포 뒤 core PC 작업자가 15692 응답을 확인하면 아래를 진행한다.

메신저를 거치면 백틱이 사라지므로 아래 명령에는 백틱이 없다. 한 줄씩 실행한다.

### 6-1. 파일 복사 (파일 그대로)

아래 6개를 run PC 작업 폴더에 **파일 그대로** 복사한다(내용을 메신저에 붙여 넣지 않는다).

| 이 폴더의 파일 | run PC 위치 |
| --- | --- |
| `run/compose.prometheus.yaml` | `observability\compose.prometheus.yaml` |
| `run/prometheus.yml` | `observability\prometheus.yml` |
| `run/grafana-datasource-prometheus.yaml` | `observability\grafana-datasource-prometheus.yaml` |
| `run/grafana-alerting-dlq.yaml` | `observability\grafana-alerting-dlq.yaml` |
| `run/Verify-DLQ.ps1` | `observability\Verify-DLQ.ps1` |
| `run/dashboards/rabbitmq-dlq.json` | `observability\dashboards\rabbitmq-dlq.json` |

```powershell
cd C:\Users\301B-00\Desktop\observability
Test-Path .\compose.prometheus.yaml, .\prometheus.yml, .\grafana-datasource-prometheus.yaml, .\grafana-alerting-dlq.yaml, .\Verify-DLQ.ps1, .\dashboards\rabbitmq-dlq.json
```

`True`가 6줄 나와야 한다. 대시보드 파일은 복사하는 순간 Grafana가 읽지만, 6-4 전에는 Prometheus 데이터 소스가 없어 패널이 비어 있다(정상).

### 6-2. Discord 웹훅 주소 넣기 (직접, 채팅으로 보내지 않음)

1. Discord에서 알림 받을 채널 → 채널 편집 → 연동 → 웹후크 → 새 웹후크 → **웹후크 URL 복사**.
2. 메모장으로 `.env`를 연다.

```powershell
notepad .env
```

3. 맨 아래 새 줄에 `DISCORD_WEBHOOK_URL=` 다음에 복사한 주소를 붙여 넣고 저장한다(따옴표 없이, 한 줄).
4. 주소를 화면에 출력하지 않고 형식만 확인한다.

```powershell
Select-String -Path .env -Pattern '^DISCORD_WEBHOOK_URL=https://(discord|discordapp)\.com/api/webhooks/' -Quiet
(Select-String -Path .env -Pattern '^DISCORD_WEBHOOK_URL=').Count
```

`True`와 `1`이 나와야 한다. 웹훅 주소는 비밀 값이다. 채팅·메신저·문서·스크린샷에 넣지 않는다.
주소가 새면 Discord에서 그 웹후크를 삭제하고 새로 만든 뒤 `.env`를 고치고 `docker compose up -d grafana`를 실행한다.

### 6-3. COMPOSE_FILE에 DLQ override 추가

`.env`를 백업하고 `COMPOSE_FILE` 줄 끝에 `;compose.prometheus.yaml`을 붙인다(두 번 실행해도 한 번만 붙는다).

```powershell
Copy-Item .env .env.bak-dlq
$f = (Resolve-Path .env).Path; $t = [IO.File]::ReadAllText($f); if ($t -notmatch 'compose\.prometheus\.yaml') { [IO.File]::WriteAllText($f, ($t -replace 'COMPOSE_FILE=compose\.yaml;compose\.loki-tailnet\.yaml', 'COMPOSE_FILE=compose.yaml;compose.loki-tailnet.yaml;compose.prometheus.yaml')) }
Select-String -Path .env -Pattern '^COMPOSE_FILE='
```

마지막 줄이 `COMPOSE_FILE=compose.yaml;compose.loki-tailnet.yaml;compose.prometheus.yaml`로 보여야 한다.

### 6-4. 검사 후 적용

```powershell
docker compose config --quiet
docker compose run --rm --no-deps --entrypoint promtool prometheus check config /etc/prometheus/prometheus.yml
docker compose up -d prometheus grafana
docker compose ps prometheus grafana
docker compose logs --tail 40 grafana
```

- 첫 줄은 아무것도 출력하지 않아야 한다. `required variable DISCORD_WEBHOOK_URL is missing`이면 6-2로 돌아간다.
- 둘째 줄은 `SUCCESS: ... is valid prometheus config file syntax`.
- Prometheus가 새로 뜨고 Grafana만 다시 만들어진다(Grafana 화면 약 20초 중단). Loki·Alloy·run 서비스는 그대로다.
  Prometheus는 호스트 포트를 열지 않으므로 Tailscale 부팅 순서 문제가 없다.
- Grafana 로그에 `finished to provision alerting`이 있고 `error`가 없어야 한다.

### 6-5. 확인 (Grafana · Discord 시험 전송)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Verify-DLQ.ps1 -SendTest
```

- Grafana `admin` 비밀번호를 묻는다.
- `PASS`가 12줄(15692 up, DLQ 2개, 업무 큐 소비자 2개, 규칙 4개, 연락 지점, 대시보드, Discord 시험 전송), 마지막에 `모든 확인 통과`.
- Discord 채널에 **⚠️ DLQ 알림 연결 시험** 메시지가 와야 한다(실제 DLQ와 무관한 시험 메시지).
- `-SendTest`를 빼면 시험 메시지 없이 확인만 한다.
- 결과 전체(PASS/FAIL/INFO 줄)를 core PC 작업자에게 보낸다. 웹훅 주소는 출력되지 않는다.

### 6-6. 수집 중단 알림 시험 (약 5분)

```powershell
docker compose stop prometheus
```

3~4분 뒤 Discord에 **⚠️ DLQ 지표 수집 중단** 이 오는지 본다(Grafana가 Prometheus를 조회하지 못한 오류 문구가 같이 온다). 확인되면 바로 되돌린다.

```powershell
docker compose start prometheus
```

1~2분 뒤 **🟢 DLQ 지표 수집 재개** 가 오면 끝. Prometheus 데이터(`prometheus-data` 볼륨)는 유지된다.

### 6-7. 대시보드

Dashboards → Wadadak → **와다닥 RabbitMQ DLQ**

| 패널 | 내용 |
| --- | --- |
| DLQ 메시지 수 (지금) | 큐별 현재 값. 0이면 초록, 1 이상이면 빨강. `수집 안 됨`은 0이 아니라 지금 못 읽는다는 뜻 |
| 지표 수집 상태 | `정상`/`중단`/`수집 안 됨` |
| DLQ 메시지 수 추이 | 최근 24시간(최대 7일). 선이 끊긴 구간은 수집이 안 된 구간 |
| 업무 큐 대기 메시지 (참고) | `wadadak.core-service`·`wadadak.run-service`. 알림 없음 |
| 업무 큐 소비자 수 (지금) | core·run 업무 큐를 지켜보는 consumer 수. 0이면 빨강(2분 이어지면 "큐 소비자 없음" 알림) |
| DLQ·소비자 알림 상태 | 알림 규칙 4개의 현재 상태 |

### 알림만 잠시 끄기

메모장으로 `grafana-alerting-dlq.yaml`을 열어 `isPaused: false` 세 곳을 `isPaused: true`로 바꾸고 저장한 뒤 실행한다.
되살릴 때는 `false`로 돌리고 같은 명령을 실행한다.

```powershell
notepad .\grafana-alerting-dlq.yaml
docker compose restart grafana
```

### 완전히 되돌리기

파일로 만든 알림 규칙은 provisioning 파일을 빼도 Grafana DB에 남고 화면·API로 지울 수 없다(2026-11-20 Grafana 13.3.1로 확인).
그대로 두면 데이터 소스가 사라진 뒤 "DLQ 지표 수집 중단"이 계속 울린다. 그래서 먼저 삭제용 파일로 지운다.
`run/grafana-alerting-dlq-remove.yaml`을 run PC 작업 폴더에 **파일 그대로** 복사한 뒤 한 줄씩 실행한다.

```powershell
Copy-Item .\grafana-alerting-dlq-remove.yaml .\grafana-alerting-dlq.yaml -Force
docker compose restart grafana
Copy-Item .env.bak-dlq .env -Force
docker compose up -d grafana
docker compose rm -s -f prometheus
Remove-Item .\dashboards\rabbitmq-dlq.json
```

1~2줄이 알림 규칙·연락 지점·템플릿을 지우고, 3~5줄이 override를 빼고 Grafana를 다시 만들며 Prometheus를 내린다.
`.env`의 `DISCORD_WEBHOOK_URL` 줄은 남는다(쓰이지 않음, 지워도 된다). Prometheus 데이터까지 지우려면
`docker volume rm wadadak-run-observability_prometheus-data`. 다시 적용할 때는 `grafana-alerting-dlq.yaml`을 원본으로 다시 복사한다.

### 고칠 때

- `grafana-alerting-dlq.yaml`(알림 문구·기준)을 고치면 `docker compose restart grafana`. 파일로 만든 규칙은 Grafana 화면에서 고칠 수 없다.
- `prometheus.yml`을 고치면 `docker compose restart prometheus`.
- 대시보드 JSON은 파일만 바꾸면 30초 안에 반영된다.
