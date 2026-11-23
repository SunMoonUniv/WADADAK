# 운영 PC 감시 (Loki · Prometheus · Grafana)

운영 PC(desktop-65isqe2, Tailscale `100.111.111.92`)의 `C:\wadadak-observability\ops`에 이 폴더를 둔다. Compose 프로젝트 `wadadak-ops-observability`.

- Loki(`100.111.111.92:3100`): 인프라 · core · run PC의 Alloy가 요약 로그를 보낸다. 7일 보관.
- Prometheus(포트 없음): 인프라 PC RabbitMQ `100.75.79.15:15692`의 큐별 메시지 수 · 소비자 수와 core(`100.64.78.38:8080`) · run(`100.73.249.33:8080`)의 앱 지표(`/actuator/prometheus`). 7일 보관.
- Grafana(`http://100.111.111.92:3000`, `admin` 로그인): 대시보드와 알림(Discord). 데이터 소스 · 알림 규칙 · 연락 지점 · 대시보드는 모두 이 폴더의 파일에서 만들어진다.

## 1. 설치

1. Docker Desktop을 켜고 **Start Docker Desktop when you sign in**을 켠다. 이미지를 PC 앞에서 받는다(SSH로 받으면 자격 증명 도우미가 실패한다).

   ```powershell
   docker pull grafana/loki:3.7.2; docker pull prom/prometheus:v3.13.5; docker pull grafana/grafana:13.3.1
   ```

2. 이 폴더를 `C:\wadadak-observability\ops`에 복사하고 `.env.example`을 `.env`로 복사해 채운다.

   ```powershell
   cd C:\wadadak-observability\ops; Copy-Item .env.example .env; notepad .env
   ```

   - `GRAFANA_ADMIN_PASSWORD`: Grafana `admin` 비밀번호. `$` 같은 특수문자는 작은따옴표로 감싼다.
   - `DISCORD_WEBHOOK_URL`: Discord 채널 → 채널 편집 → 연동 → 웹후크 → 웹후크 URL 복사. 비밀 값이다. 채팅 · 문서 · 스크린샷에 넣지 않는다. 형식만 확인한다:

     ```powershell
     Select-String -Path .env -Pattern '^DISCORD_WEBHOOK_URL=https://(discord|discordapp)\.com/api/webhooks/' -Quiet
     ```

3. 검사하고 띄운다.

   ```powershell
   docker compose config --quiet
   docker compose run --rm --no-deps loki '-config.file=/etc/loki/wadadak.yaml' '-verify-config=true'
   docker compose run --rm --no-deps --entrypoint promtool prometheus check config /etc/prometheus/prometheus.yml
   docker compose up -d
   docker compose logs --tail 40 grafana
   ```

   Grafana 로그에 `finished to provision alerting`이 있고 `error`가 없어야 한다.

4. 확인한다. `PASS`가 12줄 나오고 Discord에 **⚠️ DLQ 알림 연결 시험**이 오면 된다.

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\Verify-DLQ.ps1 -SendTest
   ```

로그를 보내는 쪽은 [core/](../core) · [run/](../run) 폴더의 Alloy다. 보내는 주소는 `LOKI_PUSH_URL`(기본 `http://100.111.111.92:3100/loki/api/v1/push`).

## 2. 대시보드 (Dashboards → Wadadak)

| 대시보드 | 내용 |
| --- | --- |
| 와다닥 core 서버 로그 | core PC(`host=core-pc`) core, 인프라 PC(`host=infra-pc`) gateway · rabbitmq · cloudflared의 오류 · 경고 수, 기동 기록, 요약 줄 |
| 와다닥 러닝 서버 로그 | run 기동 줄, 러닝 판정 · GPS 공백 검사 · 이벤트 발행 실패 줄 |
| 와다닥 RabbitMQ DLQ | DLQ 메시지 수, 수집 상태, 업무 큐 대기 메시지 · 소비자 수, 알림 상태 |
| 와다닥 앱 지표 | core · run 수집 상태, 요청 수, 5xx 비율, 응답 시간 p95, 느린 API, JVM 힙 · GC 뒤 남는 메모리, DB 연결(Hikari), CPU |

대시보드 JSON은 파일만 바꾸면 30초 안에 반영된다.

## 3. 알림

알림 규칙 4개(`grafana-alerting-dlq.yaml`): DLQ 메시지 잔류, DLQ 지표 수집 중단(인프라 PC나 RabbitMQ가 멈춤), DLQ 지표 사라짐, 큐 소비자 없음(core나 run이 브로커에서 2분 넘게 떨어짐).

앱 알림 규칙 3개(`grafana-alerting-apps.yaml`, 같은 Discord 연락 지점): 서비스 지표 수집 중단(core · run이 멈췄거나 그 PC가 끊김, 2분), 서버 오류(5xx) 비율 높음(5분 동안 5% 초과, 분당 3건 이상일 때만), JVM 메모리 부족(GC 뒤 남는 메모리가 10분 넘게 90% 초과).

- **고칠 때**: 파일을 고치고 `docker compose restart grafana`(알림 파일을 새로 더했으면 `docker compose up -d grafana`). 파일로 만든 규칙은 Grafana 화면에서 고칠 수 없다. `prometheus.yml`을 고치면 `docker compose restart prometheus`.
- **잠시 끄기**: `grafana-alerting-dlq.yaml`의 `isPaused: false` 세 곳을 `true`로 바꾸고 `docker compose restart grafana`. 되살릴 때는 `false`로.
- **완전히 지우기**: 파일로 만든 규칙은 provisioning 파일을 빼도 Grafana DB에 남는다. 삭제용 파일로 먼저 지운다.

  ```powershell
  Copy-Item .\grafana-alerting-dlq-remove.yaml .\grafana-alerting-dlq.yaml -Force
  docker compose restart grafana
  ```

  다시 쓸 때는 저장소의 `grafana-alerting-dlq.yaml`을 다시 복사한다.
- **수집 중단 알림 시험(약 5분)**: `docker compose stop prometheus` → 3~4분 뒤 "⚠️ DLQ 지표 수집 중단" → `docker compose start prometheus` → "🟢 수집 재개".

## 4. 알아 둘 점

- **부팅 순서**: Loki · Grafana 포트는 Tailscale 주소에 바인딩되어 있다. Docker가 Tailscale보다 먼저 뜨면 바인딩이 실패해 컨테이너가 뜨지 않는다. 재부팅 뒤 `docker compose ps`로 보고, 안 떴으면 `docker compose up -d`.
- **운영 PC가 꺼지면** 로그 · 알림이 모두 멈추고 알려 줄 곳도 없다. 바깥 감시는 보류했다([운영 PC](<../../운영 PC (감시 · 백업) - 2026-11-23.md>) 6장).
- **Loki가 8분 넘게 응답하지 않으면** Alloy가 재시도하다 그 배치를 버린다. 그동안의 로그는 다시 오지 않는다.
- **Grafana를 이 PC에서만 열려면** `.env`에 `GRAFANA_BIND_IP=127.0.0.1`을 넣고 `docker compose up -d grafana`.
- `docker compose down`은 컨테이너만 내리고 볼륨(로그 · 지표 · Grafana 설정)은 남긴다.
