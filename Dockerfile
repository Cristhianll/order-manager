
# syntax=docker/dockerfile:1
 
# ---------------------------------------------------------------
# Etapa 1: compilación (imagen con Maven + JDK 17, NO llega a prod)
# ---------------------------------------------------------------
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /workspace
 
# Primero solo el pom: la capa de dependencias se cachea mientras el pom no cambie
COPY pom.xml .
RUN --mount=type=cache,target=/root/.m2 mvn -B -q dependency:go-offline
 
COPY src ./src
# Las pruebas se ejecutan en el pipeline (job "test"), no en el build de la imagen
RUN --mount=type=cache,target=/root/.m2 mvn -B -q package -DskipTests
 
# ---------------------------------------------------------------
# Etapa 2: runtime (solo JRE, Alpine => imagen liviana)
# ---------------------------------------------------------------
FROM eclipse-temurin:17-jre-alpine AS runtime
 
ARG GIT_SHA=unknown
ARG BUILD_DATE=unknown
LABEL org.opencontainers.image.title="order-manager" \
      org.opencontainers.image.description="Order Manager API (DOY0101)" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.created="${BUILD_DATE}"
 
# Seguridad: parchar paquetes del sistema base (ej. CVEs de librerias Alpine)
RUN apk upgrade --no-cache
 
# Seguridad: usuario no-root con UID numerico fijo (requerido por Kubernetes runAsNonRoot)
RUN addgroup -S -g 10001 app && adduser -S -u 10001 -G app app
WORKDIR /app
COPY --from=build --chown=10001:10001 /workspace/target/*.jar app.jar
USER 10001
 
# Trazabilidad: el commit queda visible en /actuator/info
ENV GIT_SHA=${GIT_SHA} \
    JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75.0"
 
EXPOSE 8098
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD wget -qO- http://localhost:8098/actuator/health | grep -q '"status":"UP"' || exit 1
 
ENTRYPOINT ["java", "-jar", "app.jar"]
 
