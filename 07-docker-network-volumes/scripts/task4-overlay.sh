#!/usr/bin/env bash
# Task 4: Docker overlay networks.
#
# The homework only asks to *research* overlay networks. Reading about them is
# much less convincing than running one, so this script initialises a real
# single-node Swarm, creates a genuine overlay network, and demonstrates
# service discovery and load balancing across it.
set -u
hr(){ echo; echo "==================== $* ===================="; }

hr "0. WHY A SWARM IS NEEDED AT ALL"
cat <<'NOTE'
  An overlay network is a MULTI-HOST network. It needs a control plane to
  distribute network state (which container is on which host, and the VXLAN
  tunnel endpoints) between the participating Docker daemons. Docker provides
  that control plane through SWARM MODE.

  You therefore cannot create a usable overlay network on a standalone daemon:
NOTE
echo
echo "\$ docker network create -d overlay will-fail   (on a non-swarm daemon)"
docker swarm leave --force >/dev/null 2>&1
sleep 2
docker network create -d overlay will-fail 2>&1 | head -3
echo ">> Confirmed: overlay requires swarm mode."

hr "1. INITIALISE SWARM MODE"
echo "\$ docker swarm init"
docker swarm init 2>&1 | head -6
echo
echo "\$ docker node ls"
docker node ls

hr "2. CREATE AN OVERLAY NETWORK"
docker network rm app-overlay >/dev/null 2>&1
echo "\$ docker network create --driver overlay --attachable app-overlay"
docker network create --driver overlay --attachable app-overlay
echo
echo "\$ docker network ls --filter driver=overlay"
docker network ls --filter driver=overlay
echo
echo "--- what the overlay network actually looks like ---"
echo "\$ docker network inspect app-overlay --format '...'"
docker network inspect app-overlay --format 'driver={{.Driver}}
scope={{.Scope}}
attachable={{.Attachable}}
subnet={{range .IPAM.Config}}{{.Subnet}}{{end}}'
echo
echo ">> scope=SWARM (not 'local' like a bridge network) — this is the key"
echo ">> difference. A bridge network exists on ONE daemon; an overlay network"
echo ">> is known to EVERY node in the swarm."

hr "3. INGRESS — the overlay network Docker creates for you"
echo "\$ docker network ls | grep -E 'ingress|docker_gwbridge'"
docker network ls | grep -E 'NETWORK|ingress|docker_gwbridge'
echo
echo ">> 'ingress' is an overlay network Swarm creates automatically. It carries"
echo ">> the routing mesh: a request to a published port on ANY node is routed to"
echo ">> a node actually running the task. 'docker_gwbridge' connects containers"
echo ">> on the overlay out to the external network."

hr "4. DEPLOY SERVICES ON THE OVERLAY"
docker service rm web api >/dev/null 2>&1; sleep 2
echo "\$ docker service create --name web --network app-overlay --replicas 3 -p 8085:80 nginx:alpine"
docker service create --name web --network app-overlay --replicas 3 -p 8085:80 nginx:alpine 2>&1 | tail -3
echo
echo "\$ docker service create --name api --network app-overlay --replicas 2 nettools sleep infinity"
docker service create --name api --network app-overlay --replicas 2 nettools sleep infinity 2>&1 | tail -3

echo
echo "waiting for the services to converge..."
for i in $(seq 1 60); do
  w=$(docker service ls --filter name=web --format '{{.Replicas}}')
  a=$(docker service ls --filter name=api --format '{{.Replicas}}')
  if [ "$w" = "3/3" ] && [ "$a" = "2/2" ]; then echo "converged after ${i}s"; break; fi
  [ "$i" = "60" ] && echo "did not fully converge (web=$w api=$a)"
  sleep 1
done

echo
echo "\$ docker service ls"
docker service ls
echo
echo "\$ docker service ps web"
docker service ps web --format 'table {{.Name}}\t{{.Node}}\t{{.CurrentState}}'

hr "5. SERVICE DISCOVERY ACROSS THE OVERLAY"
API=$(docker ps --filter name=api. --format '{{.Names}}' | head -1)
echo "using task container: $API"
echo
echo "--- the service name resolves to a VIRTUAL IP (VIP), not a container IP ---"
echo "\$ docker exec $API dig +short web"
docker exec "$API" dig +short web 2>&1
echo
echo "\$ docker exec $API getent hosts web"
docker exec "$API" getent hosts web 2>&1
echo
echo "\$ docker service inspect web --format '{{range .Endpoint.VirtualIPs}}{{.Addr}}{{end}}'"
docker service inspect web --format '{{range .Endpoint.VirtualIPs}}{{.Addr}} {{end}}'
echo
echo ">> One stable VIP stands in front of all 3 replicas. Docker load-balances"
echo ">> to the individual tasks behind it, so callers never track replica IPs."

echo
echo "--- tasks.<service> returns the INDIVIDUAL task addresses instead ---"
echo "\$ docker exec $API dig +short tasks.web"
docker exec "$API" dig +short tasks.web 2>&1
echo ">> Three A records — one per replica. This is DNS round-robin mode,"
echo ">> useful when a client wants to see every instance itself."

hr "6. ACTUAL TRAFFIC OVER THE OVERLAY"
echo "\$ docker exec $API curl -s -o /dev/null -w 'HTTP %{http_code}\\n' http://web"
docker exec "$API" curl -s -o /dev/null -w 'HTTP %{http_code}\n' http://web
echo
echo "--- 6 requests through the VIP load balancer ---"
for i in 1 2 3 4 5 6; do
  printf '  request %d: ' "$i"
  docker exec "$API" curl -s -o /dev/null -w '%{http_code}\n' http://web
done
echo
echo "\$ curl -s -o /dev/null -w 'HTTP %{http_code}\\n' http://localhost:8085/   # via the routing mesh"
curl -s -o /dev/null -w 'HTTP %{http_code}\n' http://localhost:8085/

hr "7. HOW AN OVERLAY NETWORK WORKS ACROSS MULTIPLE HOSTS"
cat <<'NOTE'

  THE PROBLEM
    Containers on Host A get IPs from Host A's private bridge (172.17.0.0/16).
    Containers on Host B get IPs from Host B's bridge - the SAME range. The
    addresses collide, and neither host can route to the other's containers.

  THE SOLUTION: VXLAN ENCAPSULATION
    An overlay network gives every container an address from ONE logical subnet
    (e.g. 10.0.1.0/24) that spans all hosts. When a container on Host A sends a
    packet to a container on Host B, Docker:

      1. takes the original layer-2 Ethernet frame,
      2. WRAPS it in a UDP packet (VXLAN, port 4789),
      3. sends that UDP packet over the ordinary physical network to Host B,
      4. Host B unwraps it and delivers the original frame to the container.

    +---------------- Host A ----------------+   +---------------- Host B ----------------+
    |  container  10.0.1.5                   |   |  container  10.0.1.9                   |
    |      |                                 |   |      ^                                 |
    |   vxlan0  --- encapsulate in UDP/4789 -----------> vxlan0  --- decapsulate           |
    |      |                                 |   |      |                                 |
    |   eth0  192.168.1.10  ==== physical network ==== eth0  192.168.1.11                  |
    +----------------------------------------+   +----------------------------------------+

    The containers believe they are on one flat LAN. The physical network only
    ever sees ordinary UDP between two hosts - it needs no special configuration.

  THE CONTROL PLANE
    Swarm's managers keep a distributed store (gossip protocol) of which
    container has which overlay IP and which host it lives on, so every node
    knows where to send an encapsulated frame. Control traffic is encrypted by
    default; DATA traffic is not, unless you pass --opt encrypted (which turns
    on IPsec, at a CPU cost).

  PORTS THAT MUST BE OPEN BETWEEN HOSTS
    2377/tcp        cluster management (managers only)
    7946/tcp+udp    node-to-node control / gossip
    4789/udp        VXLAN data plane
    A blocked 4789/udp is the classic cause of "the service starts but the
    containers cannot talk to each other".

  WHEN TO USE WHICH DRIVER
    bridge   - single host, the default. Containers on one daemon.
    host     - single host, no isolation. See Task 2.
    overlay  - MULTIPLE hosts. Swarm services, or --attachable containers.
    macvlan  - give a container a real MAC/IP on the physical LAN.
    none     - no networking at all.

  IN PRACTICE
    Kubernetes solves the same problem with its own CNI plugins (Flannel uses
    VXLAN much like this; Calico can use BGP routing instead of encapsulation).
    The concept - one flat logical network stretched across many hosts - is the
    same everywhere.

NOTE

hr "8. CLEAN UP"
echo "\$ docker service rm web api"
docker service rm web api 2>&1
sleep 3
echo "\$ docker network rm app-overlay"
docker network rm app-overlay 2>&1
echo "\$ docker swarm leave --force"
docker swarm leave --force 2>&1
