# 와다닥 로그 수집 · RabbitMQ DLQ 감시

## 저장소의 이 폴더

감시 PC에 실제로 깔린 설정의 원본이다. 운영 배포(`deploy/compose.yaml`, `deploy/core/compose.yaml`, `deploy/run/compose.yaml`)와 따로 띄우며, GitHub Actions 배포는 이 폴더를 쓰지 않는다.
설정을 바꾸면 이 폴더를 먼저 고치고(PR), 같은 파일을 해당 PC에 복사해 적용한다.

| 폴더 | 놓는 곳 | Compose 프로젝트 | 하는 일 |
| --- | --- | --- | --- |
| [`ops/`](ops/README.md) | 운영 PC(desktop-65isqe2 · `100.111.111.92`) `C:\wadadak-observability\ops` | `wadadak-ops-observability` | Loki · Prometheus · Grafana, Discord 알림 |
| `core/` | core PC `C:\wadadak-observability\core`, 인프라 PC의 Alloy 폴더(그 폴더 `.env`에 `ALLOY_HOST=infra-pc`) | `wadadak-core-observability` | Alloy: core · gateway · rabbitmq · cloudflared 로그 |
| [`run/`](run/README.md) | run PC `C:\Users\301B-00\Desktop\observability` | `wadadak-run-observability` | Alloy: run 로그 |

**비밀 값은 저장소에 없다.** 운영 PC `ops\.env`에만 둔다(`ops/.gitignore`가 `.env`를 막는다): `GRAFANA_ADMIN_PASSWORD`, `DISCORD_WEBHOOK_URL`.
Grafana 데이터(`grafana-data` 볼륨)를 잃어도 데이터 소스 · 알림 규칙 · 연락 지점 · 대시보드는 전부 `ops/`의 파일에서 다시 만들어진다.

```text
core PC:   wadadak-core (core)                              Alloy host="core-pc"  ─┐
인프라 PC: wadadak-server (gateway, rabbitmq, cloudflared)  Alloy host="infra-pc" ─┼─ Tailscale ─► 운영 PC Loki 100.111.111.92:3100
run PC:    wadadak-run (run)                                Alloy                ─┘                         │
인프라 PC: rabbitmq 15692 ◄── Tailscale ── 운영 PC Prometheus (포트 없음, 7일) ──► 운영 PC Grafana ◄─────────┘
                                                                                     (100.111.111.92:3000) ─► Discord
```

## 폴더 구성

| 경로 | 역할 |
| --- | --- |
| `ops/compose.yaml` | Loki(3100을 운영 PC Tailscale 주소에만) · Prometheus(v3.13.5, 7일, 포트 없음) · Grafana(3000, 로그인) |
| `ops/loki.yaml` | Loki 설정(7일 보관) |
| `ops/prometheus.yml` | 수집 대상 `100.75.79.15:15692` `/metrics/detailed?vhost=/&family=queue_coarse_metrics&family=queue_consumer_count`, `rabbitmq_detailed_queue_messages` · `rabbitmq_detailed_queue_consumers`만 저장 |
| `ops/grafana-datasource*.yaml` · `ops/grafana-dashboards.yaml` | Loki(UID `wadadak-loki`) · Prometheus(UID `wadadak-prometheus`) 데이터 소스, 대시보드 폴더 |
| `ops/grafana-alerting-dlq.yaml` | Discord 연락 지점 `wadadak-discord`, 알림 문구 템플릿, 알림 규칙 4개(Wadadak 폴더, 그룹 `rabbitmq-dlq`) |
| `ops/grafana-alerting-dlq-remove.yaml` | (되돌릴 때만) 위 알림 규칙 · 연락 지점 · 템플릿 삭제용 |
| `ops/dashboards/*.json` | "와다닥 core 서버 로그" · "와다닥 러닝 서버 로그" · "와다닥 RabbitMQ DLQ" |
| `ops/Verify-DLQ.ps1` | Grafana로 15692 수집 · DLQ 값 · 규칙 · 연락 지점 · 대시보드 확인, `-SendTest`로 Discord 시험 전송 |
| `ops/Verify-Grafana.ps1` | Grafana 데이터 소스로 core smoke · 실제 core · run 로그를 조회 |
| `core/compose.yaml` · `core/config.alloy` | Alloy v1.21.0. 수집 대상 · 허용 목록 필터. 전송 주소 `LOKI_PUSH_URL`(기본 운영 PC), `host` 라벨 `ALLOY_HOST`(기본 `core-pc`) |
| `core/New-SmokeLog.ps1` | 이번 실행만의 smoke 마커를 찍고 출력 |
| `run/compose.yaml` · `run/config.alloy` · `run/verify.ps1` | run PC Alloy와 검증 |

## 수집하는 것 (core/config.alloy와 동일)

run 로그는 [run/README.md](run/README.md). core PC 로그에는 `host="core-pc"`, 인프라 PC 로그에는 `host="infra-pc"`와 Compose 서비스명으로 만든 `service` 라벨이 붙는다.
아래 요약 문장만 전송하고, 원문 줄은 보내지 않는다. 허용 목록에 없는 줄과 168시간보다 오래된 줄은 버린다.

| service | 전송하는 줄 | 원본 조건 |
| --- | --- | --- |
| `core` | `Started WadadakApplication in N seconds` | `WadadakApplication` INFO 기동 로그 |
| `core` | `Spring ERROR <로거>` | 모든 로거의 ERROR |
| `core` | `Spring WARN <로거>` | `com.wadadak.`·`c.w.` 로거의 WARN만 (Flyway·SpringDoc 등 라이브러리 WARN 제외) |
| `gateway` | `Caddy started serving` | `serving initial configuration`, `server running` |
| `gateway` | `Caddy warn/error/fatal/panic` (+ ` (HTTP handler)`) | 해당 level. `http.log.access*`(접근 로그)는 전부 제외 |
| `rabbitmq` | `RabbitMQ startup complete` | `[info] ... Server startup complete` |
| `rabbitmq` | `RabbitMQ warning/error/critical/alert/emergency` | 해당 level |
| `cloudflared` | `cloudflared: Starting tunnel` 등 | `Starting tunnel`, `Registered/Unregistered tunnel connection` |
| `cloudflared` | `cloudflared WRN/ERR/FTL` | 해당 level |
| `smoke` | `WADADAK_CORE_OBSERVABILITY_SMOKE <32hex>` | 검증용 임시 컨테이너 |

요청 로그(쿼리 문자열·IP), 예외 메시지·스택, Caddy 접근 로그, 헬스체크(`admin.api received request`)는 보내지 않는다.
오류의 자세한 내용은 그 서비스가 있는 PC에서 `docker logs`로 확인한다.

## 운영 명령 (core PC · 인프라 PC, `core` 폴더)

```powershell
docker compose run --rm --no-deps alloy validate /etc/alloy/config.alloy
docker compose up -d --force-recreate alloy
docker compose logs --tail 50 alloy
powershell -NoProfile -ExecutionPolicy Bypass -File .\New-SmokeLog.ps1
docker compose --profile smoke down
```

- `config.alloy`를 바꾸면 validate 후 `--force-recreate`로 다시 만들고, 기동 로그의 `node_id`가 설정의 컴포넌트
  (`discovery.docker.local`, `discovery.relabel.core`, `loki.source.docker.core`, `loki.process.core`, `loki.write.ops_pc`)와 맞는지 본다.
- 운영 Compose(`wadadak-server`, `--remove-orphans` 사용)와 프로젝트 이름이 달라 배포가 Alloy를 지우지 않는다.
- `docker compose down`은 컨테이너만 내리고 읽기 위치 볼륨은 남긴다. `down -v`는 읽기 위치를 지워 7일치를 다시 보낸다.

## 검증 방식

최종 조회 검증은 운영 PC Grafana(`http://100.111.111.92:3000`)로 `ops/Verify-Grafana.ps1`을 돌린다.
서비스 PC에서는 Loki API(`http://100.111.111.92:3100`)를 직접 조회해 사전 확인할 수 있다(Grafana 검증을 대신하지 않음).

Grafana Explore → Loki → Code에서 Last 7 days로:

```logql
{host=~"core-pc|infra-pc"}
{host="core-pc", service="core"}
sum by (service) (count_over_time({host=~"core-pc|infra-pc"} |~ "ERROR|error|ERR|FTL" [1h]))
{service="run"}
```

## 알아 둘 점

- **처음 가져온 옛 로그의 조회 지연:** Loki에서 한 줄짜리 옛 스트림(예: 며칠 전 RabbitMQ 기동 줄)은 메모리에 남는 동안 조회되지 않는다.
  새 줄 없이 30분이 지나 idle flush되면 보인다(2026-11-20에는 전송 약 30분 뒤인 15:06 KST에 조회됨). 새로 찍히는 로그는 바로 보인다.
- **운영 PC Loki가 꺼져 있을 때:** Alloy의 `loki.write`는 기본값으로 약 8분 재시도한 뒤 그 배치를 버린다. 읽기 위치는 이미 넘어가므로
  그동안의 로그는 다시 오지 않는다. 장시간 장애 뒤 로그 보존은 검증하지 않았다.
- **재생성 시 중복:** 읽기 위치는 초 단위로 저장되어, Alloy 재생성 직후 마지막 1초 분량을 다시 보낼 수 있다. Loki가 같은 시각·같은 줄은 중복 제거한다.
- **운영 PC 부팅 순서:** Loki · Grafana 포트는 Tailscale IP에 바인딩되어 있어, Docker가 Tailscale보다 먼저 띄우면 포트 바인딩이 실패할 수 있다.
  그때는 운영 PC `ops` 폴더에서 `docker compose up -d`를 다시 실행한다.
- **접근 제한:** tailnet에는 서버 PC 넷(인프라 · core · run · 운영)과 작업 PC가 있다. Tailscale ACL은 허용 규칙만 있다. 팀원 기기를 늘리기 전에 관리 콘솔(Access controls)에서 서버 PC끼리만 전부 허용하고, 팀원 기기에는 필요한 포트(예: `ops-pc:3000`)만 연다. Loki 3100에는 Alloy가 도는 서버 PC 셋이 닿아야 한다.

  ```jsonc
  {
    "hosts": { "infra-pc": "100.75.79.15", "core-pc": "100.64.78.38", "run-pc": "100.73.249.33", "ops-pc": "100.111.111.92" },
    "acls": [
      { "action": "accept", "src": ["infra-pc", "core-pc", "run-pc", "ops-pc"], "dst": ["infra-pc:*", "core-pc:*", "run-pc:*", "ops-pc:*"] }
    ]
  }
  ```
- **Prometheus의 `host: core-pc` 라벨:** RabbitMQ는 인프라 PC(`100.75.79.15`)에 있지만 라벨은 서버 2대 때 이름 그대로다. 바꾸면 DLQ 잔류 규칙(`last_over_time` 7일)이 옛 라벨의 시계열을 7일 동안 따로 본다.
- **DLQ 감시:** 아래 "RabbitMQ DLQ 감시" 절. core의 `/actuator/prometheus`는 범위 밖(Caddy 공개 경로 차단·배포 health 검사 영향).

## 대시보드

Dashboards → Wadadak → **와다닥 core 서버 로그**: 오류 로그 수·경고 로그 수(서비스별 막대), 서비스 기동 기록(배포·재시작),
core · 인프라 PC 전체 요약 로그. 패널 쿼리는 `ops/dashboards/core-logs.json`에 있고 위 수집 표의 요약 문장과 맞춰져 있다.
필터에 새 요약 문장을 추가하면 이 대시보드의 정규식도 함께 고친다.

## RabbitMQ DLQ 감시

### core PC에서 확인한 것 (2026-11-20, 읽기 전용)

- `wadadak-server-rabbitmq-1`: `rabbitmq:4.1-alpine`(4.1.8), hostname `rabbitmq`, 볼륨 `wadadak-server_broker`.
- `rabbitmq_prometheus`는 **이미 켜져 있다.** 공식 이미지의 기본 `/etc/rabbitmq/enabled_plugins`(`[rabbitmq_prometheus].`)라
  컨테이너를 다시 만들어도 유지된다. 15692는 컨테이너 안에서만 열려 있었다.
- vhost는 `/` 하나. DLQ `wadadak.core-service.dlq`·`wadadak.run-service.dlq`(classic, durable) 모두 있고 0건.
  업무 큐는 `x-dead-letter-routing-key=<큐>.dlq`로 기본 교환을 거쳐 DLQ로 보낸다.
- 지표 형식: `rabbitmq_detailed_queue_messages{vhost="/",queue="wadadak.core-service.dlq"} 0`.
- 배포: GitHub Actions `backend.yml`의 deploy가 `docker compose -f deploy/compose.yaml up -d --wait --remove-orphans`(프로젝트 `wadadak-server`).

### 15692 노출 (WADADAK PR #258)

<https://github.com/SunMoonUniv/WADADAK/pull/258> — `deploy/compose.yaml` rabbitmq에 `"100.75.79.15:15692:15692"`와 설명 주석 한 줄.
머지되면 배포가 rabbitmq 컨테이너를 다시 만든다(브로커 수십 초 중단, 큐·메시지는 볼륨과 고정 hostname으로 유지).
인프라 PC 분리(서버 3대) 뒤에도 rabbitmq는 `100.75.79.15`에 남는다. 지표에는 인증이 없어 Tailscale 주소에만 연다.

머지·배포 뒤 core PC에서 확인:

```powershell
docker port wadadak-server-rabbitmq-1
curl.exe -s "http://100.75.79.15:15692/metrics/detailed?vhost=%2F&family=queue_coarse_metrics" | findstr dlq
```

### 알림 규칙 (`ops/grafana-alerting-dlq.yaml`)

평가 30초마다. 경로는 규칙마다 `notification_settings`로 Discord 연락 지점 `wadadak-discord`에 보낸다(기본 알림 정책은 건드리지 않음).
그룹은 알림 이름+큐, 첫 대기 30초, 묶음 간격 1분, **재알림 4시간**.

| 알림 | 울리는 조건 | 해제(알림) | 수집이 멈췄을 때 |
| --- | --- | --- | --- |
| DLQ 메시지 잔류 (큐별) | 마지막으로 수집한 메시지 수 > 0 이 1분 지속 | 수집 중 **실제 0이 관측**되면 "DLQ 비워짐" | 상태 유지(KeepLast). no-data·오류로 해제되지 않음 |
| DLQ 지표 수집 중단 | `up` < 1, `up` 없음, Prometheus 조회 오류가 2분 지속 | 다시 `up`=1이면 "수집 재개" | 이 알림이 울린다 |
| DLQ 지표 사라짐 (큐별) | `up`=1인데 DLQ 두 개 중 하나(또는 둘)의 지표가 2분 없음 | 다시 보이면 "지표 다시 보임" | 상태 유지(KeepLast) |
| 큐 소비자 없음 (큐별, 2026-11-23 추가) | `wadadak.core-service`·`wadadak.run-service`의 `rabbitmq_detailed_queue_consumers` < 1 이 2분 지속 (서버는 떠 있는데 RabbitMQ 연결이 끊긴 경우) | 소비자가 다시 붙으면 "큐 소비자 다시 연결" | 상태 유지(KeepLast). 대신 "수집 중단"이 울린다 |

- 잔류 규칙은 `last_over_time(...[7d])`(마지막으로 실제 수집한 값)을 본다. 그래서 수집이 끊겨도 값이 0으로 바뀌거나 사라지지 않는다.
- 사라짐 규칙은 큐마다 늘 한 줄(있으면 0, 없으면 1)을 낸다. 그래서 RabbitMQ가 멈춰도 "다시 보임"으로 잘못 해제되지 않는다.
- 알림 문구: 큐 이름, 메시지 수, 발생 시각(KST), 관리자 DLQ 페이지 <https://api.leedohyunn8n.shop/admin/#failed>.
  "발생 시각"은 조건이 지속 시간을 채워 알림이 시작된 시각이라 실제 DLQ 유입보다 1~2분 늦다.
  "DLQ 비워짐"에는 "재처리가 성공했다는 뜻은 아님"을 적었다.
- Discord 웹훅 주소는 운영 PC `ops\.env`의 `DISCORD_WEBHOOK_URL`에만 있다(비밀 값, 채팅으로 받지 않음).
  Grafana는 이 값을 비밀 필드로 저장하고 API에서도 `[REDACTED]`로만 돌려준다. 다만 Grafana 컨테이너 환경 변수라 운영 PC에서 `docker inspect`로는 보인다.

### 검증

**core PC에서 직접 확인(2026-11-20, 이 세션):** 운영과 분리된 임시 Compose 프로젝트 `wadadak-dlq-test`(시험용 RabbitMQ 4.1-alpine에 같은 큐 4개,
Prometheus v3.13.5, Grafana 13.3.1, Discord 대신 요청을 기록하는 로컬 수신기, 포트는 127.0.0.1만)에 위 파일을 그대로 넣어 확인했다. 확인 뒤 모두 지웠다.
운영 RabbitMQ·DLQ에는 시험 메시지를 넣지 않았다.

| 시나리오 | 결과 |
| --- | --- |
| provisioning | 데이터 소스·연락 지점(URL은 비밀 필드)·템플릿·규칙 3개·대시보드가 오류 없이 로드, 규칙과 대시보드가 같은 Wadadak 폴더 |
| 수집 | 대상 up, 큐 4개 `rabbitmq_detailed_queue_messages`만 저장(수집 26 → 저장 4) |
| DLQ에 2건 | 1분 뒤 "🔴 DLQ 메시지 잔류 · wadadak.core-service.dlq", 메시지 수 2건, KST 시각, 관리자 링크 |
| Prometheus 정지 | 잔류 알림은 Alerting 유지(Error, KeepLast), 2분 뒤 "⚠️ DLQ 지표 수집 중단"(조회 오류 문구 포함) |
| Prometheus 재시작 | "🟢 DLQ 지표 수집 재개", 잔류 알림은 해제되지 않음 |
| DLQ 비우기 | "🟢 DLQ 비워짐"(재처리 성공 아님 문구, 잔류 시작·해제 시각) |
| DLQ 하나 삭제 | 2분 뒤 "⚠️ DLQ 지표 사라짐 · wadadak.run-service.dlq" |
| RabbitMQ 정지(up=0) | "수집 중단"만 울리고 "사라짐"은 유지(잘못된 "다시 보임" 없음) |
| RabbitMQ·큐 복구 | "🟢 수집 재개"와 "🟢 지표 다시 보임" |
| `Verify-DLQ.ps1 -SendTest`(Windows PowerShell 5.1) | PASS 9줄, 시험 메시지 "⚠️ DLQ 알림 연결 시험" 한글 정상 |
| 되돌리기 | provisioning 파일을 빼도 규칙이 DB에 남고 API 삭제는 409 → `grafana-alerting-dlq-remove.yaml`로 삭제됨 |
| run PC compose 병합 | 원본 compose + loki override + 이 override 병합 시 Grafana에 마운트 2개·환경 변수 1개만 추가, 웹훅 없으면 명확한 오류로 중단 |

**운영 적용 (2026-11-23, run PC):** PR #258 머지(11-20)·배포로 core `100.75.79.15:15692` 응답 200. run PC에 파일 6개(원본과 해시 동일)·`.env` 웹훅·`COMPOSE_FILE` 적용 후
`docker compose up -d prometheus grafana`. provisioning 오류 없음, Prometheus `up=1`, DLQ 2개 0건.
`Verify-DLQ.ps1 -SendTest` PASS 9줄·`모든 확인 통과`. Prometheus를 4분 정지해 "⚠️ DLQ 지표 수집 중단"(정지 약 3분 40초 뒤), 재시작 후 "🟢 DLQ 지표 수집 재개" 발송.
Discord에 시험·수집 중단·수집 재개 3건 도착(사용자 확인). 4시간 재알림은 설정값(`repeat_interval: 4h`)만 확인했다.

**소비자 없음 알림 추가 (2026-11-23):** 수집에 `family=queue_consumer_count`를 더하고 규칙 `wadadak-queue-consumer-zero`, 대시보드 패널 "업무 큐 소비자 수 (지금)"을 추가해 run PC에 적용했다.
promtool SUCCESS, provisioning 오류 없음, 규칙 쿼리가 업무 큐 2개(core·run 각 소비자 1)만 잡고 평가 오류 0. 운영 서비스를 끊어 실제로 울려 보지는 않았다.
배포로 core·run 컨테이너가 다시 만들어지는 동안은 소비자가 잠깐 0이 되므로 `for: 2m`으로 넘긴다. 배포가 2분보다 오래 걸리면 알림이 갈 수 있다.

### 알아 둘 점 (DLQ)

- run PC에 SSH로 접속한 세션에서는 Docker Desktop 자격 증명 도우미(`credsStore: desktop`)가 `A specified logon session does not exist`로 실패해 이미지 pull이 안 된다.
  run PC 앞에서 직접 pull하거나, 도우미가 PATH에 없는 임시 폴더에 `docker.exe` 사본과 빈 `config.json`을 두고 `--config`로 공개 이미지만 받는다(2026-11-23 사용).

- DLQ가 0이어도 재처리가 성공했다는 뜻은 아니다. 되돌린 메시지가 다시 실패하면 DLQ로 돌아온다.
- DLQ에 없어도 리스너 처리 오류는 아웃박스 `common.event_publication`·`run.event_publication`에 남을 수 있다. 이 감시는 브로커 단계만 본다.
- 회원 탈퇴 이벤트가 DLQ에 남았다는 것은 해당 소비 서비스의 후속 처리가 지연될 수 있다는 뜻이다. 건수만으로 특정 회원의 데이터 상태를 확정하지 않는다.
- 운영 PC가 꺼지면 수집과 알림이 모두 멈춘다(알림도 오지 않음). 바깥 감시는 보류했다(`deploy/운영 PC (감시 · 백업) - 2026-11-23.md` 6장).
- 메시지가 남은 채로 DLQ 큐가 지워지면 잔류 알림은 최대 7일 유지되다가 "⚪ DLQ 잔류 알림 정리 (지표 없음)"으로 정리된다.
- 파일로 만든 알림 규칙은 Grafana 화면에서 고칠 수 없다. 파일을 고치고 운영 PC에서 `docker compose restart grafana`.
- 제안(팀 합의 미확인): 알림을 맡는 사람이 Discord 스레드에 "제가 볼게요"를 남기고 처리·재처리 결과도 같은 스레드에 남긴다.
