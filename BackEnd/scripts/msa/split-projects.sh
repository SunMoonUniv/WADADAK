#!/bin/sh
# MSA 분리 3단계(개발 정책 11.3): BackEnd/src를 Gradle 서브프로젝트로 옮긴다. 파일 이동만 하고 내용은 바꾸지 않는다.
# 구성은 deploy/MSA 분리 준비와 CI·CD 3장. Gradle 파일·Dockerfile·설정은 따로 커밋한다.
#
# 사용: scripts/msa/split-projects.sh   (BackEnd/src가 있는 깨끗한 작업 트리에서)
# main이 바뀌면 이동 커밋을 rebase하지 않는다. 그 커밋을 버리고 새 main 위에서 이 스크립트를 다시 돌린다.
set -eu
cd "$(dirname "$0")/../.."

J=src/main/java/com/wadadak
R=src/main/resources
T=src/test/java/com/wadadak
M=$R/db/migration

mv_() {
    mkdir -p "$(dirname "$2")"
    git mv "$1" "$2"
}

# --- main: 공유 jar (개발 정책 3.3) ---
mv_ $J/common/region libs/common-region/$J/common/region
mv_ $J/common/storage libs/common-storage/$J/common/storage
mv_ $J/common libs/common-core/$J/common
mv_ $J/event libs/event/$J/event

mv_ $M/common/V20261007_0900__common_init.sql libs/common-core/$M/common/V20261007_0900__common_init.sql
for f in V20261007_2100__common_postgis.sql V20261008_1000__common_region.sql V20261008_1001__common_region_seed.sql; do
    mv_ $M/common/$f libs/common-region/$M/common/$f
done
mv_ $M/common/V20261017_1200__common_photo_uploads.sql libs/common-storage/$M/common/V20261017_1200__common_photo_uploads.sql

# --- main: 계약 jar (모듈 루트의 공개 타입) ---
for f in $J/course/*.java; do mv_ "$f" "libs/course-api/$f"; done
for f in $J/ranking/*.java; do mv_ "$f" "libs/ranking-api/$f"; done

# --- main: run 모듈 (라이브러리. 전환 전까지 core가 함께 담는다) ---
mv_ $J/run modules/run/$J/run
mv_ $M/run modules/run/$M/run

# --- main: 나머지는 core 서비스 ---
mv_ src/main services/core/src/main

# --- test ---
# 공유 테스트 픽스처
mv_ $T/TestcontainersConfiguration.java libs/common-core/src/testFixtures/java/com/wadadak/TestcontainersConfiguration.java

# 단위 테스트는 jar로 옮긴다. 컨텍스트를 띄우는 테스트는 애플리케이션 클래스가 있는 서비스에 둔다.
for d in config entity exception geo outbox stub; do mv_ $T/common/$d libs/common-core/$T/common/$d; done
mv_ $T/common/storage/ObjectStorageTest.java libs/common-storage/$T/common/storage/ObjectStorageTest.java
mv_ $T/course/GpsGapRuleTest.java libs/course-api/$T/course/GpsGapRuleTest.java

# run 테스트: @ApplicationModuleTest는 run 서비스, 단위 테스트는 modules/run.
# @SpringBootTest(GpsSourceLinkTest: course 내부를 함께 쓴다)는 core에 남긴다. 전환 PR에서 나눈다.
find $T/run -name '*.java' | while read -r f; do
    if grep -q '@ApplicationModuleTest' "$f"; then
        mv_ "$f" "services/run/$f"
    elif ! grep -q '@SpringBootTest' "$f"; then
        mv_ "$f" "modules/run/$f"
    fi
done

mv_ src/test services/core/src/test
rmdir src
