#!/usr/bin/env bash
# Host-side networking commands (macOS). Some things are only real on a real
# machine on a real LAN: the routing table, the ARP cache of actual neighbours,
# and a traceroute that is not swallowed by Docker Desktop's NAT.
set -u
hr(){ echo; echo "==================== $* ===================="; }
run(){ echo; echo "\$ $*"; eval "$@" 2>&1 | head -${N:-20}; }

hr "A. INTERFACES (macOS uses ifconfig; Linux uses 'ip addr')"
N=30 run "ifconfig en0"
run "networksetup -listallhardwareports | head -12"
run "ipconfig getifaddr en0"

hr "B. ROUTING TABLE — the REAL default gateway"
run "netstat -rn -f inet | head -15"
run "route -n get default"

hr "C. ARP CACHE — real neighbours on the LAN"
N=15 run "arp -a"
echo
echo ">> Each line maps an IP on the local segment to a MAC address."
echo ">> ARP is how a host finds the hardware address for the next hop."

hr "D. DNS"
run "cat /etc/resolv.conf"
run "scutil --dns | head -12"
run "dig +short github.com"
run "nslookup github.com"

hr "E. TRACEROUTE — a real path across the internet"
N=25 run "traceroute -I -m 15 -w 1 -q 1 google.com"
echo
echo ">> Hop 1 is the home router, hops 2-5 the ISP's network,"
echo ">> then Google's edge, then the destination."

hr "F. LISTENING PORTS ON THIS MACHINE"
run "netstat -an -p tcp | grep LISTEN | head -15"
run "lsof -nP -iTCP -sTCP:LISTEN | head -12"

hr "G. LATENCY & REACHABILITY"
run "ping -c 4 8.8.8.8"
run "ping -c 3 github.com"

hr "H. HTTP TIMING BREAKDOWN"
run "curl -s -o /dev/null -w 'dns=%{time_namelookup}s connect=%{time_connect}s tls=%{time_appconnect}s ttfb=%{time_starttransfer}s total=%{time_total}s code=%{http_code}\\n' https://github.com"
run "curl -s ifconfig.me"
echo
