# run PC 로그 수집 (Alloy)

run PC(desktop-266eggn)의 `C:\Users\301B-00\Desktop\observability`에 이 폴더를 둔다. Compose 프로젝트 `wadadak-run-observability`.
Alloy가 `wadadak-run`의 run 컨테이너 로그에서 아래 줄만 골라 운영 PC Loki(`LOKI_PUSH_URL`, 기본 `http://100.111.111.92:3100/loki/api/v1/push`)로 보낸다.

| 보내는 줄 | 원본 |
| --- | --- |
| `Started RunServiceApplication in N seconds` | 기동 |
| `Free run processing failed for <기록 ID>` · `GPS gap check failed for <ID>` · `Run event publication failed for <ID>` | 러닝 판정 · GPS 공백 검사 · 이벤트 발행 워커 예외 |
| `Spring ERROR <로거>` | 모든 로거의 ERROR (위 작업 실패 줄은 그 줄로 보낸다) |
| `Spring WARN <로거>` | `com.wadadak.`·`c.w.` 로거의 WARN만 (예: 이벤트 10분 밀림 `EventMonitor`). Flyway·SpringDoc 등 라이브러리 WARN은 뺀다 |
| `WADADAK_OBSERVABILITY_SMOKE <시각>` | 검증용 `smoke` 컨테이너 |

요청 로그, 예외 메시지 · 스택은 보내지 않는다. 자세한 내용은 run PC에서 `docker logs wadadak-run-run-1`로 본다. 168시간보다 오래된 줄은 버린다.
운영 PC 알림은 "core · run 로그 경보"(ERROR, `EventMonitor`)와 "run 작업 실패"(작업 실패 줄)가 본다([ops/README.md](../ops/README.md) 3장).

## 띄우기 · 고치기

```powershell
cd C:\Users\301B-00\Desktop\observability
docker compose run --rm --no-deps alloy validate /etc/alloy/config.alloy
docker compose up -d --remove-orphans alloy
```

- `config.alloy`를 고치면 같은 두 줄을 다시 돌린다(`--force-recreate`가 필요하면 붙인다).
- 읽기 위치는 볼륨 `wadadak-run-observability_alloy-data`에 있다. `docker compose down -v`는 읽기 위치를 지워 7일치를 다시 보낸다.

## 확인

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\verify.ps1
```

운영 PC Grafana `admin` 비밀번호를 묻는다. `smoke` 컨테이너가 이번 실행의 표식을 한 줄 찍고, Grafana로 그 줄과 최근 7일의 run 줄을 찾아 둘 다 `PASS`면 된다.
