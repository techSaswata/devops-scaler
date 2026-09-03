#!/usr/bin/env bash
# Task 1: build and run the multi-stage image, and compare it against a
# single-stage build of the identical application.
cd "$(dirname "$0")/multistage-app"

echo "############ 1. BUILD the MULTI-STAGE image ############"
echo '$ docker build -t multistage-app:latest .'
docker rm -f multistage-app >/dev/null 2>&1
docker build -t multistage-app:latest . 2>&1 | tail -25

echo
echo "############ 2. BUILD the SINGLE-STAGE image (for comparison) ############"
echo '$ docker build -f Dockerfile.single-stage -t singlestage-app:latest .'
docker build -f Dockerfile.single-stage -t singlestage-app:latest . 2>&1 | tail -8

echo
echo "############ 3. SIZE COMPARISON ############"
echo '$ docker images | grep -E "multistage-app|singlestage-app|golang"'
docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}' \
  | grep -E 'REPOSITORY|multistage-app|singlestage-app|golang'

echo
# Two different measures, and they legitimately disagree -- so report both.
#   `docker images` SIZE  = layers UNPACKED on disk (what the daemon stores)
#   `inspect .Size`       = the COMPRESSED content size (what gets pulled/pushed)
# Under Docker Desktop's containerd image store these differ noticeably, and
# quoting one number as if it were the other is a common way to be wrong.
MS_C=$(docker image inspect multistage-app:latest  --format '{{.Size}}')
SS_C=$(docker image inspect singlestage-app:latest --format '{{.Size}}')
MS_D=$(docker images --format '{{.Size}}' multistage-app:latest)
SS_D=$(docker images --format '{{.Size}}' singlestage-app:latest)

echo "                    unpacked on disk   compressed content"
printf '  multi-stage       %-18s %s MB\n' "$MS_D" "$(echo "scale=2; $MS_C/1000000" | bc)"
printf '  single-stage      %-18s %s MB\n' "$SS_D" "$(echo "scale=2; $SS_C/1000000" | bc)"
echo
echo "  reduction (compressed) : $(echo "scale=1; 100 - ($MS_C*100/$SS_C)" | bc)% smaller"
echo "  ratio     (compressed) : $(echo "scale=1; $SS_C/$MS_C" | bc)x"

echo
echo "############ 4. WHAT IS ACTUALLY INSIDE THE FINAL IMAGE? ############"
echo '$ docker image inspect multistage-app --format "{{len .RootFS.Layers}} layer(s)"'
docker image inspect multistage-app:latest --format '{{len .RootFS.Layers}} layer(s)'
echo
echo '$ docker history multistage-app:latest'
docker history multistage-app:latest --format 'table {{.CreatedBy}}\t{{.Size}}' | head -10

echo
echo "############ 5. RUN the container on PORT 8080 ############"
echo '$ docker run -d --name multistage-app -p 8080:8080 multistage-app:latest'
docker run -d --name multistage-app -p 8080:8080 multistage-app:latest

echo
echo "waiting for the app to answer..."
for i in $(seq 1 30); do
  code=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/ 2>/dev/null)
  if [ "$code" = "200" ]; then echo "HTTP 200 after ${i}s"; break; fi
  sleep 1
done

echo
echo "############ 6. VERIFY with docker ps — running on port 8080 ############"
echo '$ docker ps --filter name=multistage-app'
docker ps --filter name=multistage-app --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
echo
echo '$ docker port multistage-app'
docker port multistage-app

echo
echo "############ 7. VERIFY the application output ############"
echo '$ curl -s http://localhost:8080/ | grep -o "Hello World from Docker multi-stage build"'
curl -s http://localhost:8080/ | grep -o "Hello World from Docker multi-stage build"
echo
echo '$ curl -s -o /dev/null -w "HTTP %{http_code} (%{size_download} bytes)\n" http://localhost:8080/'
curl -s -o /dev/null -w "HTTP %{http_code} (%{size_download} bytes)\n" http://localhost:8080/
echo
echo '$ docker logs multistage-app'
docker logs multistage-app 2>&1 | head -5

echo
echo "############ 8. PROOF the final image has no shell / no OS ############"
# NOTE: the Dockerfile uses ENTRYPOINT, so a trailing "/bin/sh" would be passed
# as an ARGUMENT to /server rather than replacing it -- the server would just
# start and block forever. --entrypoint is what actually overrides it.
echo '$ docker run --rm --entrypoint /bin/sh multistage-app:latest   (expected to FAIL)'
docker run --rm --entrypoint /bin/sh multistage-app:latest 2>&1 | head -3
echo
echo '$ docker run --rm --entrypoint /bin/ls multistage-app:latest /   (expected to FAIL)'
docker run --rm --entrypoint /bin/ls multistage-app:latest / 2>&1 | head -3
echo
echo '$ docker exec multistage-app sh    (cannot debug a scratch container this way)'
docker exec multistage-app sh 2>&1 | head -3
echo
echo ">> There is no shell, no ls, no package manager, no libc in the image."
echo ">> Nothing to exploit and nothing to patch — that is the security win of"
echo ">> a scratch-based multi-stage build, on top of the size win."
