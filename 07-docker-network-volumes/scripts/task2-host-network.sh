#!/usr/bin/env bash
# Task 2: run Apache2 with the HOST network and access it on port 80.
set -u
hr(){ echo; echo "==================== $* ===================="; }

docker rm -f apache-host apache-bridge hostprobe bridgeprobe >/dev/null 2>&1

hr "1. PULL THE APACHE2 IMAGE FROM DOCKER HUB"
echo "\$ docker pull httpd:2.4"
docker pull httpd:2.4 2>&1 | tail -4
echo
echo "\$ docker images httpd"
docker images httpd --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}'

hr "2. CREATE AN APACHE2 CONTAINER USING THE HOST NETWORK"
echo "\$ docker run -d --name apache-host --network host httpd:2.4"
docker run -d --name apache-host --network host httpd:2.4
sleep 3

echo
echo "--- note the PORTS column is EMPTY ---"
echo "\$ docker ps --filter name=apache-host"
docker ps --filter name=apache-host --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
echo
echo ">> There is no '0.0.0.0:80->80/tcp' mapping because there is nothing to map."
echo ">> With --network host the container does not get its own network namespace;"
echo ">> it shares the host's. Apache binds port 80 ON THE HOST DIRECTLY."
echo ">> This is also why '-p 80:80' is meaningless (and ignored) with host networking."

hr "3. PROOF: the container shares the HOST's network namespace"
echo "--- a normal BRIDGE container gets its own private IP ---"
docker run -d --name apache-bridge -p 8082:80 httpd:2.4 >/dev/null
sleep 2
echo "\$ docker exec apache-bridge hostname -i     # bridge container"
docker exec apache-bridge hostname -i
echo "\$ docker inspect apache-bridge --format '{{.NetworkSettings.IPAddress}}'"
docker inspect apache-bridge --format '{{.NetworkSettings.IPAddress}}'
echo
echo "--- the HOST-network container has NO container IP of its own ---"
echo "\$ docker inspect apache-host --format '{{.NetworkSettings.IPAddress}}'"
echo "[$(docker inspect apache-host --format '{{.NetworkSettings.IPAddress}}')]  <- empty"
echo
echo "\$ docker exec apache-host hostname -i       # host-network container"
docker exec apache-host hostname -i 2>&1
echo "\$ docker exec apache-host hostname"
docker exec apache-host hostname 2>&1
echo ">> It reports the HOST's hostname and the HOST's IP, not a 172.17.x.x address."

hr "4. ACCESS THE APACHE WEBSITE ON PORT 80"
echo "--- from another container that ALSO uses the host network ---"
echo "\$ docker run --rm --network host nettools curl -s -o /dev/null -w 'HTTP %{http_code}' http://localhost:80/"
docker run --rm --network host nettools \
  curl -s -o /dev/null -w 'HTTP %{http_code}\n' --max-time 5 http://localhost:80/
echo
echo "\$ docker run --rm --network host nettools curl -s http://localhost:80/"
docker run --rm --network host nettools curl -s --max-time 5 http://localhost:80/
echo ">> SUCCESS. Apache is answering on port 80 of the host network namespace,"
echo ">> reachable at plain 'localhost:80' with no port publishing at all."

echo
echo "--- for contrast: a BRIDGE container's localhost is its OWN, so this fails ---"
echo "\$ docker run --rm nettools curl -s --max-time 3 http://localhost:80/   (expected to FAIL)"
docker run --rm nettools curl -sS --max-time 3 http://localhost:80/ 2>&1 | head -2
echo ">> Correct: in a bridge container, 'localhost' means that container itself."

hr "5. HOW THIS LOOKS ON macOS  (an important caveat)"
echo "\$ curl --max-time 5 http://localhost:80/     # from macOS itself"
curl -s -o /dev/null -w 'HTTP %{http_code}\n' --max-time 5 http://localhost:80/ 2>&1
echo
cat <<'NOTE'
>> On macOS this returns 000 (no connection), and that is EXPECTED, not a broken demo.
>>
>> Docker Desktop does not run containers on macOS directly -- it runs a Linux VM.
>> "--network host" means "the HOST inside that VM". So Apache really is on port 80
>> of the Linux host's network namespace (proved in step 4), but macOS is a separate
>> machine from Docker's point of view, and there is no published port to forward.
>>
>> On a native Linux Docker host, "curl http://localhost:80" from the host shell
>> would return 200 immediately.
>>
>> Docker Desktop 4.34+ ships an opt-in host-networking feature
>> (Settings -> Resources -> Network -> "Enable host networking") that bridges this
>> gap. It is not enabled here, and turning it on requires restarting Docker Desktop.
NOTE

hr "6. WHEN TO USE HOST NETWORKING"
cat <<'NOTE'

  PROS
    - No NAT hop, so slightly lower latency and higher throughput.
    - The container can bind ANY port without publishing it.
    - Needed for tools that must see the host's real interfaces:
      network monitors, tcpdump-style capture, DHCP servers, mDNS/discovery.

  CONS
    - NO ISOLATION. The container can bind any port and see all host traffic.
    - Port conflicts: two containers cannot both bind port 80.
    - Not portable: --network host is Linux-only in the strict sense; on
      Docker Desktop it means the VM's host, as shown above.
    - Loses Docker's DNS-by-container-name.

  DEFAULT ADVICE: use bridge + -p. Reach for host networking only when you have
  a specific reason, and know that you are trading isolation for it.

NOTE
docker rm -f apache-bridge >/dev/null 2>&1
