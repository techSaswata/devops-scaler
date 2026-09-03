# ---------- Stage 1: BUILD ----------
# The full JDK (with javac) is needed to compile, but not to run.
FROM eclipse-temurin:21-jdk AS build

WORKDIR /build
COPY src/HelloWorld.java .

# Compile to bytecode, then package into a runnable JAR with a Main-Class manifest
RUN javac -d classes HelloWorld.java && \
    jar --create --file app.jar --main-class HelloWorld -C classes .

# ---------- Stage 2: RUNTIME ----------
# Only the JRE ships in the final image — no compiler, no source. Roughly half
# the size of the JDK image and a smaller attack surface.
FROM eclipse-temurin:21-jre

LABEL maintainer="Saswata Das <24BCS10248>"
LABEL description="Hello World web application in Java"

WORKDIR /app
COPY --from=build /build/app.jar .

RUN useradd --create-home --shell /bin/bash app && chown -R app:app /app
USER app

ENV PORT=8080
EXPOSE 8080

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -fsS http://127.0.0.1:8080/health >/dev/null || exit 1

CMD ["java", "-jar", "app.jar"]
