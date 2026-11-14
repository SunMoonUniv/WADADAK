#!/usr/bin/env bash
# 한 번 측정: ./run.sh <태그> [k6 -e 옵션...]   예) ./run.sh course -e MODULE=course -e RATE=20
# 서버(8090) · 부하 DB 컨테이너(wadadak-loadtest-db)가 떠 있어야 한다. 결과는 results/<태그>.*
# 서버는 -XX:FlightRecorderOptions:stackdepth=1024로 띄운다(기본 64면 깊은 스택에서 모듈 프레임이 잘린다)
set -euo pipefail
cd "$(dirname "$0")"
TAG=$1; shift
DB="docker exec wadadak-loadtest-db psql -U wadadak -d wadadak -Atq"
JAVA_BIN="${JAVA_HOME:-/c/Program Files/Java/jdk-21.0.11}/bin"
PID=$("$JAVA_BIN/jcmd" | awk '/WADADAK-BackEnd/ {print $1}')
TOKEN=$(curl -s -X POST localhost:8090/api/v1/members/auth/login -H 'Content-Type: application/json' -d '{"provider":"KAKAO","token":"lt-user-0"}' | sed -E 's/.*"accessToken":"([^"]+)".*/\1/')
cpu_ns() { curl -s localhost:8090/actuator/metrics/process.cpu.time -H "Authorization: Bearer $TOKEN" | sed -E 's/.*"value":([0-9.E]+).*/\1/'; }
backlog() { $DB -c "select count(*) from run.sessions where processing='PROCESSING'"; }

$DB -c "create extension if not exists pg_stat_statements; select pg_stat_statements_reset();" >/dev/null
JFR="$(pwd -W 2>/dev/null || pwd)/results/$TAG.jfr"
# profile 설정에서 실행 샘플만 1ms마다로(기본 10~20ms는 요청이 짧아 샘플이 너무 적다)
JFC="$(pwd -W 2>/dev/null || pwd)/results/lt.jfc"
[ -f results/lt.jfc ] || sed 's|control="method-sampling-java-interval">[^<]*<|control="method-sampling-java-interval">1 ms<|' "$JAVA_BIN/../lib/jfr/profile.jfc" > results/lt.jfc
OUT=$("$JAVA_BIN/jcmd" "$PID" JFR.start name=lt settings="$JFC" filename="$JFR")
echo "$OUT" | grep -q "Started recording" || { echo "$OUT"; exit 1; }
CPU0=$(cpu_ns); T0=$(date +%s)

MSYS_NO_PATHCONV=1 docker run --rm -v "$(pwd -W 2>/dev/null || pwd):/lt" -w /lt -e TAG="$TAG" "$@" grafana/k6:1.0.0 run --quiet modules.js \
  | grep -v '^time=' > "results/$TAG.k6.txt" || true
T1=$(date +%s)
# 업로드한 기록의 판정(백그라운드 워커)까지 끝나야 run의 비용이 다 잡힌다
while [ "$(backlog)" != "0" ]; do sleep 2; done
T2=$(date +%s)

CPU1=$(cpu_ns)
"$JAVA_BIN/jcmd" "$PID" JFR.stop name=lt >/dev/null
$DB -c "copy (select query, calls, total_exec_time from pg_stat_statements where dbid=(select oid from pg_database where datname='wadadak')) to stdout with csv header" > "results/$TAG.db.csv"

python - "$CPU0" "$CPU1" "$T0" "$T1" "$T2" > "results/$TAG.summary.txt" <<'EOF'
import sys
c0, c1, t0, t1, t2 = map(float, sys.argv[1:])
print(f"부하 {t1-t0:.0f}s, 기록 판정 대기 {t2-t1:.0f}s, 서버 CPU {(c1-c0)/1e9:.1f} 코어·초 (평균 {(c1-c0)/1e9/max(t2-t0,1):.2f} 코어)")
EOF
python analyze.py cpu "results/$TAG.jfr" >> "results/$TAG.summary.txt"
python analyze.py db "results/$TAG.db.csv" >> "results/$TAG.summary.txt"
cat "results/$TAG.k6.txt" "results/$TAG.summary.txt"
