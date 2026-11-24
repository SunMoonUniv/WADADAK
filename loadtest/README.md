# 부하 테스트

여정(사용자 흐름)별로 부하를 올려 어디서 느려지는지 찾고, run을 떼면 나아지는지 본다.
결과 문서: [`deploy/모듈 부하 테스트 - 2026-11-14.md`](../deploy/모듈%20부하%20테스트%20-%202026-11-14.md)(모놀리스) · [`deploy/MSA 이후 부하 테스트 - 2026-11-24.md`](../deploy/MSA%20이후%20부하%20테스트%20-%202026-11-24.md)(core · run 분리 뒤)

## 준비물

Docker, JDK 21, Python 3, Git. 메모리는 여유 8GB 이상(DB 컨테이너 · 서버 JVM 2GB · 부하 발생기 k6).

## 1. DB · 서버 띄우기

```bash
# 부하용 DB(개발 DB 5433과 별개). pg_stat_statements는 run.sh(모듈 단위 측정)에서만 쓴다
docker run -d --name wadadak-loadtest-db -p 5434:5432 --shm-size=1g -e POSTGRES_DB=wadadak -e POSTGRES_USER=wadadak -e POSTGRES_PASSWORD=wadadak postgis/postgis:17-3.5 -c shared_preload_libraries=pg_stat_statements -c max_connections=200
```

```bash
# BackEnd/에서: JWT 키(README 1번과 같다) · jar
mkdir -p .local/jwt && openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out .local/jwt/private.pem && openssl pkey -in .local/jwt/private.pem -pubout -out .local/jwt/public.pem
./gradlew :services:core:bootJar
```

```bash
# BackEnd/에서: 서버. 가짜 소셜 로그인(토큰 문자열 = 소셜 ID)과 지표 노출을 켠다. 처음 뜰 때 마이그레이션에 30초쯤 걸린다
DB_URL=jdbc:postgresql://localhost:5434/wadadak java -Xms1g -Xmx2g -jar services/core/build/libs/core-0.0.1-SNAPSHOT.jar --app.member.social.fake=true --management.endpoints.web.exposure.include=health,metrics --server.port=8090
```

## 2. 시드 (약 20분)

```bash
# loadtest/에서. 회원 600 · 코스 600 · 기록 3,000(판정이 초당 3.4건이라 15분쯤 기다린다) · 리뷰 약 600
python ramp.py seed
```

## 3. 측정

```bash
# 워밍업(JIT). 결과는 쓰지 않는다
python ramp.py day 2 --duration 60
```

```bash
# 여정별 증가: 초당 여정 수를 단계별로 올린다(단계마다 40초). 약 45분
for spec in "home 10,20,40,80,160,320" "detail 10,20,40,80,160,320" "ranking 10,20,40,80,160,320" "my 10,20,40,80,160,320" "register 1,2,4,8,15" "run 1,2,3,4,6,8,12,16"; do set -- $spec; python ramp.py $1 $2; done
```

```bash
# 하루 흐름 통합 증가: 사용자 1명의 하루(여정 6개를 한 번씩)를 초당 N명씩
python ramp.py day 1,2,3,4,6,8,10,12,15 --probe
```

```bash
# 분리 실험: 같은 DB로 서버를 하나 더(--server.port=8091) 띄우고, run 요청만 그쪽으로 보낸다
python ramp.py day 1,2,3,4,6,8,10,12,15 --probe --split
```

- 결과: `results/ramp-<여정>.jsonl`(단계마다 한 줄), `results/<여정>-<속도>.json`.
- 코스 등록은 회원마다 하루 한 번이라, `register` · `day`는 한 단계에 회원 600명까지만 쓴다(속도 × 40초 ≤ 600). 단계 사이에 부하 테스트가 등록한 코스(이름 `LT…`)를 지우고 한도를 되돌린다.
- 판정이 밀리는 단계는 다음 단계 전에 다 끝날 때까지 기다린다(`판정대기`).

## 4. MSA 이후(서버 PC 셋)

운영 core · run을 잠깐 멈추고 같은 PC에 부하용 스택(`msa/`, 프로젝트 이름 `wadadak-lt`)을 띄운다. 운영 이미지 그대로이고 DB는 비어 있다. 가짜 로그인 · 부하용 JWT 키로 뜬다. 부하는 이 저장소를 연 PC에서 Tailscale로 바로 건다(게이트웨이를 거치지 않는다).

| PC | 파일 | 포트 |
| --- | --- | --- |
| 인프라 PC | `msa/broker.yaml` | 5673 (운영 브로커는 5672 그대로) |
| core PC | `msa/core.yaml` + `.env`(`LT_JWT_PUBLIC_KEY` · `LT_JWT_PRIVATE_KEY`, PEM을 base64 한 줄로) | 18080 |
| run PC | `msa/run.yaml` + `.env`(`LT_JWT_PUBLIC_KEY`) | 18081 |

```powershell
# 각 PC의 C:\wadadak-loadtest\에서. 운영 앱만 멈춘다(운영 DB · graphhopper는 그대로)
docker stop wadadak-core-core-1    # core PC. run PC는 wadadak-run-run-1
docker compose -f core.yaml up -d  # run PC는 run.yaml, 인프라 PC는 broker.yaml
```

```bash
# loadtest/에서. 시드 · 측정 명령은 2 · 3번과 같고 LT_MSA=1만 붙인다(--split은 쓰지 않는다)
LT_MSA=1 python ramp.py seed
LT_MSA=1 python ramp.py day 1,2,3,4,6,8,10,12,15 --probe
```

- `PC CPU`는 core PC/run PC 순서로 둘 다 적는다(서버 JVM이 보는 Docker VM 전체 CPU라 DB도 들어 있다). `풀대기`는 core/run의 DB 커넥션 풀을 기다린 스레드 수의 최댓값이다.
- 조회 여정은 초당 320회까지만 건다. 640회는 부하 발생 PC의 Docker(k6)가 멈췄다.
- 끝나면 각 PC에서 `docker compose -f <파일> down -v`로 부하용 스택을 지우고 `docker start wadadak-core-core-1`(run PC는 `wadadak-run-run-1`)로 운영을 되돌린다.

## 여정

| 여정 | 흐름 (앱 코드 기준 호출) | 요청 수 |
| --- | --- | --- |
| `home` 홈 탐색 | 알림 수, 지도 3번 움직임, 목록(인기순), 현재 러너 수 3번(1분마다 · 3분 머묾) | 8 |
| `detail` 코스 상세 | 상세, 저장 여부, 랭킹 요약 · 목록, 리뷰 요약 · 내 리뷰 · 목록 | 7 |
| `run` 러닝 1회 | 코스 러닝(준비 · 시작 · 구간 종료) 50% 또는 자유 러닝 30분 50%, 원본 500개씩 업로드, 상태, (판정 끝났으면) 결과 · 구간 | 6~11 |
| `register` 코스 등록 | 하루 한도까지: 사용자 지정 1개 + GPS 기록 기반 3개(원본 경로 → 미리 보기 → 등록) | 13 |
| `ranking` 랭킹 탭 | 누적 거리 요약 · 목록, 지역 주간 요약 · 목록, 다른 러너 프로필 · 총 거리 | 6 |
| `my` MY 탭 | 내 정보, 기록 목록, 등록한 코스 · 요약, 저장한 코스 요약, 알림 목록 | 6 |
| `day` 하루 흐름 | 위 6개를 한 번씩 (러닝 하루 1회, 코스 등록 하루 한도 4개) | 약 50 |

## 판단 기준

| 항목 | 기준 | 근거 |
| --- | --- | --- |
| 실패 | 응답 오류 또는 15초 초과 | 앱의 응답 제한(`FrontEnd/app/lib/core/api/api_client.dart` `receiveTimeout`) |
| 성능저하 시작 | p95 ≥ 100ms 이고 가장 낮은 단계의 2배 이상 | 0.1초: 즉시 반응한다고 느끼는 한계(닐슨의 응답 시간 기준) |
| 한계 | p95 ≥ 1초 또는 실패율 ≥ 1% | 1초: 흐름이 끊기지 않는 한계(같은 기준) |
| 판정 밀림 | 단계가 끝난 뒤 판정대기 > 15초 | 앱이 통신 실패 뒤 처음 다시 시도하는 간격(`run_controller.dart`) |
| PC 한계 | 단계의 `PC CPU` ≥ 90% | 부하 발생기 · DB · 서버가 같은 PC면, 이 단계는 서버가 아니라 PC가 막힌 것일 수 있다 |

## 동시 사용자 · DAU 환산

- 하루 흐름 초당 N명 = 피크 1시간에 N × 3,600명이 하루치 사용을 한다.
- 피크 1시간에 하루 사용의 10~15%가 몰린다고 본다(러닝 피크는 저녁 6~7시. 운동의 약 29%가 오후 5~9시 4시간에, 시드니 러닝의 30%가 아침 3시간에 몰린다는 공개 자료 기준).
- **감당 가능한 DAU = 한계 직전 속도 × 3,600 ÷ 피크 비중.** 예: 초당 3명, 15% → 72,000명.

## 파일

| 파일 | 내용 |
| --- | --- |
| `load.js` | 여정 정의(k6) |
| `ramp.py` | 시드, 단계별 증가, 판정 대기, 한도 되돌리기 |
| `seed.js` · `lib.js` | 시드 데이터, 공용(로그인 · GPS 원본 생성 · 응답 시간 집계) |
| `modules.js` · `run.sh` · `analyze.py` | 모듈 단위 1차 측정(문서의 결과 1~4): 모듈별 CPU · DB 비용 |
| `msa/` | MSA 이후 측정(4번)의 PC별 부하용 스택 |
