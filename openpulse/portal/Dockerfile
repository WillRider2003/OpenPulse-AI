FROM maven:3.9.12-eclipse-temurin-21 AS build
WORKDIR /build
COPY pom.xml .
RUN mvn -B -ntp dependency:go-offline
COPY src ./src
RUN mvn -B -ntp -DskipTests package

FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /build/target/openpulse-portal-1.0.0.jar /app/portal.jar
USER 10001:10001
EXPOSE 8092
ENTRYPOINT ["java","-jar","/app/portal.jar"]
