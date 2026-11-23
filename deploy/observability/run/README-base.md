# 와다닥 run PC 로그 수집 시작하기

`run` PC의 실행 중인 Docker 컨테이너에서 Alloy가 로그를 읽고 Loki로 보냅니다. Grafana는 같은 Compose 안의 Loki를 자동으로 연결합니다. 모니터링 Compose 프로젝트 이름은 `wadadak-run-observability`입니다.

## 1. run PC에서 준비

이 폴더를 통째로 `run` PC에 복사합니다. Docker Desktop의 Linux 컨테이너 엔진이 켜져 있어야 합니다. PowerShell에서 이 폴더를 열고 다음을 실행합니다.

```powershell
docker info --format '{{.OSType}}'
docker ps --filter 'label=com.docker.compose.project=wadadak-run' --filter 'label=com.docker.compose.service=run'
if (-not (Test-Path -LiteralPath .env)) { Copy-Item .env.example .env }
notepad .env
```

첫 명령은 `linux`를 반환하고, 두 번째 명령에는 기존 `run` 컨테이너가 보여야 합니다. `.env`는 처음 한 번 복사하고 `GRAFANA_ADMIN_PASSWORD`에 고유한 비밀번호를 넣습니다. `$` 등 특수문자를 그대로 쓰려면 값을 작은따옴표로 감쌉니다. 기존 `.env`가 있다면 그 파일을 편집합니다.

`GRAFANA_BIND_IP` 기본값은 `127.0.0.1`입니다. `run` PC에서 먼저 접속을 확인합니다. 팀원 PC에서 접속해야 하면 값을 `run` PC의 Tailscale IPv4 주소로 바꾸고, Tailscale에서 허용된 팀원만 접속할 수 있게 합니다.

## 2. Loki와 Grafana부터 실행

```powershell
docker compose config --quiet
docker compose pull
docker compose run --rm --no-deps loki '-config.file=/etc/loki/wadadak.yaml' '-verify-config=true'
docker compose run --rm --no-deps alloy validate /etc/alloy/config.alloy
docker compose up -d --force-recreate loki grafana
docker compose ps
```

`run` PC에서 [Grafana](http://127.0.0.1:3000)에 `admin`과 `.env`에 설정한 비밀번호로 로그인합니다. Tailscale IP를 사용했다면 그 IP의 `3000` 포트로 접속합니다. Grafana의 **Connections → Data sources**에 `Loki`가 표시됩니다. 연결 테스트가 바로 실패하면 `docker compose logs --tail 30 loki grafana`에서 기동 상태를 확인합니다.

## 3. Alloy를 띄우고 두 종류의 로그 확인

```powershell
docker compose up -d --force-recreate alloy
.\verify.ps1
```

검증 스크립트에는 Grafana 로그인 정보를 입력합니다. Tailscale 주소로 열었다면 `-GrafanaUrl 'http://<run PC의 Tailscale IP>:3000'`을 붙입니다. 스크립트는 `smoke`라는 임시 컨테이너에서 이번 실행의 시각이 포함된 로그를 한 줄 찍고, Grafana의 Loki 데이터 소스를 거쳐 그 줄과 실제 `run` 로그를 각각 조회합니다. **두 줄 모두 `PASS`**가 나오면 완료입니다. 테스트가 끝나면 임시 컨테이너를 정리합니다.

직접 확인하려면 Grafana의 **Explore → Loki → Code**에서 아래 쿼리를 각각 실행합니다. `smoke`는 **Last 15 minutes**, `run`은 **Last 7 days**로 조회합니다. `smoke` 로그의 시각이 이번 검증 실행과 일치하는지 확인합니다.

```logql
{service="smoke"} |= "WADADAK_OBSERVABILITY_SMOKE"
```

```logql
{service="run"}
```

스크립트 없이 테스트 로그를 찍으려면 `docker compose --profile smoke up -d --force-recreate smoke`를 실행합니다. 조회 뒤 `docker compose --profile smoke rm --stop --force smoke`로 임시 컨테이너를 정리합니다.

`smoke`는 보이는데 `run`이 비어 있으면 Docker 원본에 수집 대상 로그가 있는지 확인합니다. 아래 이름은 배포 기본값입니다. 1단계 출력에 다른 이름이 보이면 그 이름을 사용합니다.

```powershell
docker logs --since 168h wadadak-run-run-1 2>&1 | Select-String 'Started RunServiceApplication in |Free run processing failed for |GPS gap check failed for |Run event publication failed for '
```

원본이 비어 있다면 다음 예정된 배포의 기동 로그로 확인합니다. 연결 시험 때문에 운영 중인 `run`을 재시작할 필요는 없습니다. 원본에 로그가 있거나 `smoke`도 보이지 않으면 `docker compose logs --tail 80 alloy loki`에서 Docker 읽기 오류와 Loki 전송 오류를 확인합니다.

Grafana의 **Dashboards → Wadadak → 와다닥 러닝 서버 로그**에 원본 로그와 판정 예외 시간 그래프가 함께 있습니다. 아래 집계식은 **Explore → Code**에서도 실행할 수 있습니다. 선택한 기간에 판정 예외가 없으면 그래프는 비어 있을 수 있습니다. 재시도에서 같은 기록이 여러 번 실패하면 예외 횟수만큼 집계됩니다.

```logql
sum(count_over_time({service="run"} |= "Free run processing failed for" [5m]))
```

## 수집 및 보관 범위

- 기존 `wadadak-run` Compose의 `run` 서비스에서 기동 메시지와 판정·GPS 공백 검사·이벤트 발행 워커 예외 요약만 수집합니다. 워커 예외에는 기록 ID를 남기고, 요청 로그·전체 예외 스택은 복사하지 않습니다.
- Loki의 로그 보관 정책은 7일입니다. Loki 데이터, Grafana 설정, Alloy 읽기 위치는 Docker 볼륨에 저장합니다.
- Loki와 Alloy는 호스트에 포트를 열지 않습니다. Alloy가 Docker 로그를 읽으려면 로컬 Docker 소켓에 접근해야 하므로 이 수집기는 신뢰하는 운영자만 관리합니다.
- 멈출 때는 **이 폴더에서** `docker compose --profile smoke down`을 실행합니다. 모니터링 컨테이너만 내리고 일반 `down`은 데이터 볼륨을 보존합니다.
