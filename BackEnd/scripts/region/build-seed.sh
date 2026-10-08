#!/bin/sh
# 법정구역 경계 shapefile(국가공간정보포털 AL_D001)로 common.region 시드 마이그레이션을 만든다.
# 시·군·구(SIG)·읍·면·동(EMD)만 쓰고 리(LIO)는 쓰지 않는다.
#
# 사용: docker compose up -d 후 scripts/region/build-seed.sh ~/Downloads/AL_D001_00_20260909
# 경계 데이터가 갱신되면 새 폴더로 다시 돌리고, 결과는 새 버전 파일명으로 저장한다(머지된 마이그레이션은 수정하지 않음, 개발 정책 6.5).
set -eu

SRC=$(cd "${1:?AL_D001 폴더 경로를 넘긴다}" && pwd)
cd "$(dirname "$0")/../.."

OUT=${OUT:-src/main/resources/db/migration/common/V20261008_1001__common_region_seed.sql}
# 경계 단순화 허용 오차(m). 클수록 파일이 작고 경계가 거칠다.
TOLERANCE_M=${TOLERANCE_M:-10}
DB=region_build
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

for kind in SIG EMD; do
    unzip -q -o "$SRC"/*"($kind).zip" -d "$WORK/$kind"
done

run() { docker compose exec -T postgres "$@"; }
sql() { run psql -v ON_ERROR_STOP=1 -q -U wadadak "$@"; }

sql -d wadadak -c "DROP DATABASE IF EXISTS $DB" -c "CREATE DATABASE $DB"
sql -d $DB -c "CREATE EXTENSION postgis"

run rm -rf /tmp/region
docker compose cp "$WORK" postgres:/tmp/region
# 원본은 EPSG:5186(중부원점 TM), 속성은 CP949다.
run sh -c "shp2pgsql -s 5186 -W CP949 -D /tmp/region/SIG/*.shp sig | psql -v ON_ERROR_STOP=1 -q -U wadadak -d $DB"
run sh -c "shp2pgsql -s 5186 -W CP949 -D /tmp/region/EMD/*.shp emd | psql -v ON_ERROR_STOP=1 -q -U wadadak -d $DB"

orphans=$(sql -d $DB -At -c "SELECT count(*) FROM emd WHERE left(a1, 5) NOT IN (SELECT a1 FROM sig)")
if [ "$orphans" != 0 ]; then
    echo "시·군·구를 찾지 못한 읍·면·동 ${orphans}건은 빠진다" >&2
fi

{
    echo "-- 생성: scripts/region/build-seed.sh $(basename "$SRC"), 경계 단순화 ${TOLERANCE_M}m. 직접 수정하지 않는다."
    sql -d $DB -At <<SQL
WITH sido AS (SELECT DISTINCT ON (left(a1, 2)) left(a1, 2) || '00000000' AS code, split_part(a2, ' ', 1) AS name
              FROM sig
              ORDER BY left(a1, 2), a1),
     rows AS (SELECT code, 'SIDO' AS level, name, name AS full_name, NULL::geometry AS boundary
              FROM sido
              UNION ALL
              SELECT a1 || '00000', 'SIGUNGU', coalesce(nullif(substr(a2, strpos(a2, ' ') + 1), ''), a2), a2, NULL
              FROM sig
              UNION ALL
              SELECT e.a1 || '00', 'EUPMYEONDONG', e.a2, s.a2 || ' ' || e.a2,
                     ST_Multi(ST_Transform(ST_SimplifyPreserveTopology(e.geom, $TOLERANCE_M), 4326))
              FROM emd e
                       JOIN sig s ON s.a1 = left(e.a1, 5))
SELECT format('INSERT INTO common.region VALUES (%L, %L, %L, %L, %L);', code, level, name, full_name, boundary)
FROM rows
ORDER BY code;
SQL
} > "$OUT"

sql -d wadadak -c "DROP DATABASE $DB"
run rm -rf /tmp/region
echo "$OUT ($(du -h "$OUT" | cut -f1), $(($(wc -l < "$OUT") - 1))행)"
