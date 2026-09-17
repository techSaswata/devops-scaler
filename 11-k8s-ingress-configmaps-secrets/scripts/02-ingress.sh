#!/usr/bin/env bash
# Module 11, part 2 — Ingress. Lab checklist items 5-8 and 10,
# plus host-based routing and TLS termination.
set -u
hr(){ echo; echo "=== $* ==="; }
run(){ echo; echo "\$ $*"; eval "$@" 2>&1 | head -${N:-30}; }
M="$(cd "$(dirname "$0")/.." && pwd)/manifests"

kubectl delete ingress --all --ignore-not-found >/dev/null 2>&1
sleep 2

hr "1. WHY INGRESS EXISTS"
cat <<'NOTE'
  Without it, every service you want to expose needs its own entry point:

      type: LoadBalancer  x 10 services  =  10 cloud load balancers, 10 bills,
                                            10 IPs, 10 certificates to manage

  An Ingress is ONE entry point that routes by HOST and PATH to many services.
  One load balancer, one IP, one place to terminate TLS.

  TWO SEPARATE THINGS, often confused:
    Ingress RESOURCE    - the YAML rules. Inert on its own.
    Ingress CONTROLLER  - the pod that READS those rules and does the routing.
                          Without a controller, an Ingress resource does nothing
                          at all. This is the #1 "my ingress doesn't work" cause.
NOTE

hr "2. THE INGRESS CONTROLLER  [checklist 5]"
run "kubectl get pods -n ingress-nginx"
run "kubectl get svc -n ingress-nginx ingress-nginx-controller"
run "kubectl get ingressclass"
echo ">> The controller is Running. 'nginx' is the IngressClass that Ingress"
echo ">> resources reference via spec.ingressClassName."
echo
echo ">> Installed with the kind-specific manifest, which makes the controller"
echo ">> listen on host ports 80/443 of the control-plane node. On minikube the"
echo ">> equivalent is 'minikube addons enable ingress'; on EKS/GKE you install"
echo ">> ingress-nginx via Helm and it provisions a cloud load balancer."

hr "3. PATH-BASED ROUTING  [checklist 6]"
run "cat $M/05-ingress-path.yaml | tail -24"
run "kubectl apply -f $M/05-ingress-path.yaml"
echo
printf 'waiting for the Ingress to get an ADDRESS'
for i in $(seq 1 60); do
  ADDR=$(kubectl get ingress yatri-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
  [ -n "$ADDR" ] && { echo " - got $ADDR after ${i}s"; break; }
  printf '.'; sleep 1
done
echo
run "kubectl get ingress"
echo ">> ADDRESS is populated  [checklist 6]. The controller has accepted the rules."
run "kubectl describe ingress yatri-ingress | sed -n '/Rules:/,/Annotations:/p'"

hr "4. TEST THE ROUTES  [checklist 7 and 8]"
echo ">> yatri.local is not in /etc/hosts, so the Host header is set explicitly."
echo ">> This is exactly what a browser would send after a DNS entry existed."
echo
echo "--- path /  ->  the FRONTEND  [checklist 7] ---"
echo "\$ curl -s -H 'Host: yatri.local' http://localhost/ | head -20"
curl -s -H 'Host: yatri.local' http://localhost/ 2>&1 | head -20
echo
echo "\$ curl -s -o /dev/null -w 'HTTP %{http_code}\\n' -H 'Host: yatri.local' http://localhost/"
curl -s -o /dev/null -w 'HTTP %{http_code}\n' -H 'Host: yatri.local' http://localhost/
echo
echo "--- path /api/  ->  the BACKEND  [checklist 8] ---"
echo "\$ curl -s -H 'Host: yatri.local' http://localhost/api/"
curl -s -H 'Host: yatri.local' http://localhost/api/ 2>&1
echo
echo ">> The backend echoes the ConfigMap and Secret values it was injected with."
echo ">> PASSWORD_LENGTH is 14 - no trailing-newline bug."
echo
echo "--- the rewrite-target annotation in action ---"
echo ">> The request was /api/ but the backend received /. Without"
echo ">> nginx.ingress.kubernetes.io/rewrite-target: /\$2 the backend would have"
echo ">> been asked for /api/ and returned 404."
echo
echo "--- load balancing across the 2 backend pods ---"
for i in 1 2 3 4; do
  printf '  request %d: ' "$i"
  curl -s -H 'Host: yatri.local' http://localhost/api/ | grep '^pod' | tr -d '\n'; echo
done
echo
echo "--- an UNKNOWN host gets nothing ---"
echo "\$ curl -s -o /dev/null -w 'HTTP %{http_code}\\n' -H 'Host: nope.local' http://localhost/"
curl -s -o /dev/null -w 'HTTP %{http_code}\n' -H 'Host: nope.local' http://localhost/
echo ">> 404 from the default backend: no rule matches that Host."

hr "5. HOST-BASED ROUTING"
run "kubectl apply -f $M/06-ingress-host.yaml"
sleep 6
run "kubectl get ingress yatri-host-ingress"
echo
echo "--- two hostnames, ONE IP, different services ---"
echo "\$ curl -H 'Host: portal.yatri.local' http://localhost/ | grep -o '<title>.*</title>'"
curl -s -H 'Host: portal.yatri.local' http://localhost/ | grep -o '<title>[^<]*</title>'
echo
echo "\$ curl -H 'Host: api.yatri.local' http://localhost/ | head -4"
curl -s -H 'Host: api.yatri.local' http://localhost/ | head -4
echo
echo ">> Same IP, same port. The controller reads the HTTP Host header and picks"
echo ">> the backend. This is virtual hosting, and it is why one load balancer"
echo ">> can serve every service in the cluster."

hr "6. TLS TERMINATION"
echo "--- generate a self-signed certificate for secure.yatri.local ---"
echo "\$ openssl req -x509 -nodes -days 365 -newkey rsa:2048 \\"
echo "    -keyout tls.key -out tls.crt -subj '/CN=secure.yatri.local'"
# openssl writes key-generation progress dots to stderr; drop them.
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /tmp/tls.key -out /tmp/tls.crt \
  -subj "/CN=secure.yatri.local" \
  -addext "subjectAltName=DNS:secure.yatri.local" >/dev/null 2>&1 \
  && echo "generated /tmp/tls.crt and /tmp/tls.key"
ls -l /tmp/tls.crt /tmp/tls.key | awk '{print "  " $5 " bytes  " $9}'
echo
echo "--- store it in a Secret of type kubernetes.io/tls ---"
kubectl delete secret yatri-tls-secret --ignore-not-found >/dev/null 2>&1
echo "\$ kubectl create secret tls yatri-tls-secret --cert=tls.crt --key=tls.key"
kubectl create secret tls yatri-tls-secret --cert=/tmp/tls.crt --key=/tmp/tls.key
run "kubectl get secret yatri-tls-secret"
echo ">> TYPE is kubernetes.io/tls, not Opaque. It must contain exactly the keys"
echo ">> tls.crt and tls.key, and it must live in the SAME namespace as the Ingress."
run "kubectl get secret yatri-tls-secret -o jsonpath='{range .data}{\"\"}{end}keys: ' ; kubectl get secret yatri-tls-secret -o go-template='{{range \$k,\$v := .data}}{{\$k}} {{end}}'"
echo
run "kubectl apply -f $M/07-ingress-tls.yaml"
sleep 8
run "kubectl get ingress yatri-tls-ingress"
echo ">> Note the PORTS column now shows 80, 443."
echo
echo "--- HTTPS works (-k accepts the self-signed cert) ---"
echo "\$ curl -sk -o /dev/null -w 'HTTP %{http_code}\\n' -H 'Host: secure.yatri.local' https://localhost/"
curl -sk -o /dev/null -w 'HTTP %{http_code}\n' --resolve secure.yatri.local:443:127.0.0.1 https://secure.yatri.local/
echo
echo "--- the certificate the controller is serving ---"
echo "\$ openssl s_client -connect localhost:443 -servername secure.yatri.local </dev/null | openssl x509 -noout -subject -issuer -dates"
echo | openssl s_client -connect localhost:443 -servername secure.yatri.local 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates 2>/dev/null
echo
echo "--- plain HTTP now REDIRECTS to HTTPS (ssl-redirect: true) ---"
echo "\$ curl -s -o /dev/null -w 'HTTP %{http_code} -> %{redirect_url}\\n' -H 'Host: secure.yatri.local' http://localhost/"
curl -s -o /dev/null -w 'HTTP %{http_code} -> %{redirect_url}\n' -H 'Host: secure.yatri.local' http://localhost/
echo
echo ">> 308 Permanent Redirect. TLS is TERMINATED at the controller: it decrypts,"
echo ">> then forwards PLAIN HTTP to the pod inside the cluster. The pod needs no"
echo ">> certificate at all - which is why one Ingress can serve TLS for every"
echo ">> service behind it. In production, cert-manager issues and renews these"
echo ">> certificates from Let's Encrypt automatically."

hr "7. ALL INGRESSES"
run "kubectl get ingress"
