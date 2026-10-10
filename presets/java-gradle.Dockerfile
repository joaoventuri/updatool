# syntax=docker/dockerfile:1
# updatool preset — Java/Kotlin (Gradle)
FROM gradle:8-jdk21 AS build
WORKDIR /src
COPY . .
RUN --mount=type=cache,target=/home/gradle/.gradle \
    gradle bootJar --no-daemon -x test && cp build/libs/*.jar /app.jar

FROM eclipse-temurin:21-jre
COPY --from=build /app.jar /app.jar
EXPOSE 8080
CMD ["java", "-jar", "/app.jar"]
