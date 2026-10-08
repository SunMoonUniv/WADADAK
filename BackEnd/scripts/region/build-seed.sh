#!/bin/sh
# 법정구역 경계 shapefile(국가공간정보포털 AL_D001)로 common.region 시드 마이그레이션을 만든다.
# 시·군·구(SIG)·읍·면·동(EMD)만 쓰고 리(LIO)는 쓰지 않는다.
#
# 사용: scripts/region/build-seed.sh ~/Downloads   (AL_D001_*(SIG).zip, AL_D001_*(EMD).zip이 있는 폴더)
# Docker만 있으면 된다. 개발 DB와 별개인 일회용 PostGIS 컨테이너에서 변환하고 끝나면 지운다.
# 경계 데이터가 갱신되면 새 폴더로 다시 돌리고, 결과는 새 버전 파일명으로 저장한다(머지된 마이그레이션은 수정하지 않음, 개발 정책 6.5).
set -eu

SRC=$(cd "${1:?AL_D001 zip이 있는 폴더 경로를 넘긴다}" && pwd)
cd "$(dirname "$0")/../.."

OUT=${OUT:-src/main/resources/db/migration/common/V20261008_1001__common_region_seed.sql}
# 경계 단순화 허용 오차(m). 클수록 파일이 작고 경계가 거칠다.
TOLERANCE_M=${TOLERANCE_M:-30}
# 변환 전용. 개발 DB 이미지(postgis/postgis:17-3.5)는 Debian 11이라 지원이 끝나 apt 설치를 믿을 수 없어 Debian 13 이미지에 PostGIS를 설치해 쓴다.
IMAGE=postgres:17.6-trixie
CONTAINER=wadadak-region-build-$$
WORK=$(mktemp -d)
# Windows Git Bash가 컨테이너 안 경로(/tmp/...)를 Windows 경로로 바꾸지 않게 한다.
export MSYS_NO_PATHCONV=1
trap 'rm -rf "$WORK"; docker rm -f "$CONTAINER" >/dev/null 2>&1 || true' EXIT

for kind in SIG EMD; do
    unzip -q -o "$SRC"/*"($kind).zip" -d "$WORK/$kind"
done

# 포트를 열지 않고 끝나면 지우는 컨테이너라 비밀번호 없이 띄운다.
docker run -d --name "$CONTAINER" -e POSTGRES_USER=wadadak -e POSTGRES_HOST_AUTH_METHOD=trust "$IMAGE" >/dev/null
run() { docker exec -i "$CONTAINER" "$@"; }
sql() { run psql -v ON_ERROR_STOP=1 -q -U wadadak -d wadadak "$@"; }

# PostGIS 확장과 shp2pgsql(postgis 패키지)을 설치한다. 결과는 표준 SQL이라 개발 DB의 PostGIS 3.5에 그대로 들어간다.
run sh -c "apt-get update -qq && apt-get install -y -qq --no-install-recommends postgresql-17-postgis-3 postgis >/dev/null"
# 초기화 중에는 소켓으로만 받으므로 TCP로 붙을 때까지 기다린다.
until run pg_isready -q -h 127.0.0.1 -U wadadak; do sleep 1; done
sql -c "CREATE EXTENSION postgis"

# 경로 변환을 피하려고 docker cp 대신 tar 스트림으로 넣는다.
run mkdir -p /tmp/region
tar -C "$WORK" -cf - . | run tar -xf - -C /tmp/region
# 원본은 EPSG:5186(중부원점 TM), 속성은 CP949다.
for kind in SIG EMD; do
    table=$(echo "$kind" | tr 'A-Z' 'a-z')
    run sh -c "shp2pgsql -s 5186 -W CP949 -D /tmp/region/$kind/*.shp $table | psql -v ON_ERROR_STOP=1 -q -U wadadak -d wadadak >/dev/null"
done

# 20260909 원본 EMD에는 지번 단위 조각(코드가 '1001 ??'처럼 깨진 행)이 섞여 있다. 같은 자리의 진짜 읍·면·동은 따로 있으므로 버린다.
junk=$(sql -At -c "DELETE FROM emd WHERE a1 !~ '^[0-9]{8}\$' RETURNING 1" | wc -l)
echo "코드가 읍·면·동 형식이 아닌 행 ${junk}건을 버렸다" >&2
# 원본에는 자기 교차 등으로 형상이 잘못된 동이 있다. 단순화 전에 고친다.
sql -c "SET client_min_messages = warning" -c "UPDATE emd SET geom = ST_Multi(ST_CollectionExtract(ST_MakeValid(geom), 3)) WHERE NOT ST_IsValid(geom)"
# 20260909 원본 SIG에는 부산 남구가 두 번 들어 있다. 경계는 쓰지 않으므로 한 행만 남긴다.
sql -c "DELETE FROM sig a USING sig b WHERE a.a1 = b.a1 AND a.gid > b.gid"
dup=$(sql -At -c "SELECT string_agg(a1, ',') FROM (SELECT a1 FROM emd GROUP BY a1 HAVING count(*) > 1) d")
if [ -n "$dup" ]; then
    echo "읍·면·동 코드 중복: $dup" >&2
    exit 1
fi
# 20260909 원본 SIG에는 대구 남구가 없다. 경계는 쓰지 않으므로 이름만 채운다.
sql -c "INSERT INTO sig (a1, a2) SELECT v.* FROM (VALUES ('27200', '대구광역시 남구')) v(a1, a2) WHERE v.a1 NOT IN (SELECT a1 FROM sig)"
# 20260909 원본 SIG의 시·도 이름 오기('전북특별차지도', '제주도')를 정식 명칭으로 고친다.
sql -c "UPDATE sig SET a2 = regexp_replace(regexp_replace(a2, '^전북특별차지도 ', '전북특별자치도 '), '^제주도 ', '제주특별자치도 ')"

orphans=$(sql -At -c "SELECT count(*) FROM emd WHERE left(a1, 5) NOT IN (SELECT a1 FROM sig)")
if [ "$orphans" != 0 ]; then
    echo "시·군·구를 찾지 못한 읍·면·동 ${orphans}건은 빠진다" >&2
fi

{
    echo "-- 생성: scripts/region/build-seed.sh $(cd "$WORK/EMD" && ls *.shp), 경계 단순화 ${TOLERANCE_M}m. 직접 수정하지 않는다."
    sql -At <<SQL
WITH sido AS (SELECT DISTINCT ON (left(a1, 2)) left(a1, 2) || '00000000' AS code, split_part(a2, ' ', 1) AS name
              FROM sig
              ORDER BY left(a1, 2), a1),
     rows AS (SELECT code, 'SIDO' AS level, name, name AS full_name, NULL AS boundary
              FROM sido
              UNION ALL
              SELECT a1 || '00000', 'SIGUNGU', coalesce(nullif(substr(a2, strpos(a2, ' ') + 1), ''), a2), a2, NULL
              FROM sig
              UNION ALL
              SELECT e.a1 || '00', 'EUPMYEONDONG', e.a2, s.a2 || ' ' || e.a2,
                     -- 출력 반올림으로 다시 깨지지 않게 좌표를 소수 5자리(약 1m) 격자에 올리면서 유효하게 만든다.
                     ST_AsEWKT(ST_Multi(ST_CollectionExtract(ST_ReducePrecision(ST_MakeValid(
                             ST_Transform(ST_SimplifyPreserveTopology(e.geom, $TOLERANCE_M), 4326)), 0.00001), 3)), 5)
              FROM emd e
                       JOIN sig s ON s.a1 = left(e.a1, 5))
SELECT format('INSERT INTO common.region VALUES (%L, %L, %L, %L, %L);', code, level, name, full_name, boundary)
FROM rows
ORDER BY code;
SQL
} > "$OUT"

echo "$OUT ($(du -h "$OUT" | cut -f1), $(($(wc -l < "$OUT") - 1))행)"
