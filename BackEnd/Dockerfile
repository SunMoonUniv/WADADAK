# 공용 서버 배포 이미지(deploy/README.md). 테스트는 CI(backend.yml)가 먼저 돌리고, 여기서는 실행 JAR만 만든다.
FROM eclipse-temurin:21-jdk AS build
WORKDIR /src
COPY gradlew settings.gradle build.gradle ./
COPY gradle gradle
COPY src/main src/main
# Gradle 배포판·의존성은 BuildKit 캐시에 남겨 다음 배포에서 다시 받지 않는다.
RUN --mount=type=cache,target=/root/.gradle \
    chmod +x gradlew && ./gradlew --no-daemon bootJar && cp build/libs/*.jar app.jar

FROM eclipse-temurin:21-jre
RUN useradd --system wadadak
WORKDIR /app
COPY --from=build /src/app.jar app.jar
USER wadadak
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
