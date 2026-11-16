# 공용 서버 배포 이미지(deploy/README.md). 빌드 컨텍스트는 BackEnd. 테스트는 CI(backend.yml)가 먼저 돌리고, 여기서는 실행 JAR만 만든다.
# run 서비스만 담는다(deploy/MSA 분리 준비와 CI·CD 7.1). core 코드가 바뀌어도 이 이미지의 캐시는 그대로다.
FROM eclipse-temurin:21-jdk AS build
WORKDIR /src
COPY gradlew settings.gradle build.gradle gradle.properties ./
COPY gradle gradle
COPY libs libs
COPY modules/run modules/run
COPY services/run services/run
# settings.gradle에 include된 프로젝트 폴더가 없으면 Gradle이 실패한다. 다른 프로젝트는 build.gradle만 넣는다
COPY services/core/build.gradle services/core/
# Gradle 배포판·의존성은 BuildKit 캐시에 남겨 다음 배포에서 다시 받지 않는다.
RUN --mount=type=cache,target=/root/.gradle \
    chmod +x gradlew && ./gradlew --no-daemon :services:run:bootJar && cp services/run/build/libs/*.jar app.jar

FROM eclipse-temurin:21-jre
RUN useradd --system wadadak
WORKDIR /app
COPY --from=build /src/app.jar app.jar
USER wadadak
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
