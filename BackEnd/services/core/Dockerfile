# 공용 서버 배포 이미지(deploy/README.md). 빌드 컨텍스트는 BackEnd. 테스트는 CI(backend.yml)가 먼저 돌리고, 여기서는 실행 JAR만 만든다.
# MSA 분리 3단계: core가 modules/run을 함께 담아 지금 모놀리스와 같은 이미지다(deploy/MSA 분리 준비와 CI·CD 7.1).
FROM eclipse-temurin:21-jdk AS build
WORKDIR /src
COPY gradlew settings.gradle build.gradle gradle.properties ./
COPY gradle gradle
COPY libs libs
COPY modules modules
COPY services/core services/core
# settings.gradle에 include된 프로젝트 폴더가 없으면 Gradle이 실패한다. run 서비스는 build.gradle만 넣는다
COPY services/run/build.gradle services/run/
# Gradle 배포판·의존성은 BuildKit 캐시에 남겨 다음 배포에서 다시 받지 않는다.
RUN --mount=type=cache,target=/root/.gradle \
    chmod +x gradlew && ./gradlew --no-daemon :services:core:bootJar && cp services/core/build/libs/*.jar app.jar

FROM eclipse-temurin:21-jre
RUN useradd --system wadadak
WORKDIR /app
COPY --from=build /src/app.jar app.jar
USER wadadak
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
