#!/usr/bin/env bash
# Module 11, part 1 — ConfigMaps and Secrets.
# Lab checklist items 1-4 and 9.
set -u
hr(){ echo; echo "=== $* ==="; }
run(){ echo; echo "\$ $*"; eval "$@" 2>&1 | head -${N:-30}; }
M="$(cd "$(dirname "$0")/.." && pwd)/manifests"

kubectl delete deploy,svc,ingress,cm,secret -l app=yatri-app --ignore-not-found >/dev/null 2>&1
kubectl delete deploy yatri-backend yatri-frontend --ignore-not-found >/dev/null 2>&1
kubectl delete svc yatri-backend-service yatri-frontend-service --ignore-not-found >/dev/null 2>&1
kubectl delete cm yatri-app-config yatri-frontend-html --ignore-not-found >/dev/null 2>&1
kubectl delete secret yatri-db-secret --ignore-not-found >/dev/null 2>&1
sleep 3

hr "1. WHY CONFIGMAPS EXIST"
cat <<'NOTE'
  Without one, configuration is baked into the image:

      ENV ENVIRONMENT=production        # in the Dockerfile

  That means a separate image per environment, a rebuild to change a log level,
  and no way to see current config without cracking the image open.

  A ConfigMap decouples config from the image: ONE image, many environments.
NOTE

hr "2. CREATE THE CONFIGMAP  [checklist 1]"
run "cat $M/01-configmap.yaml | head -14"
run "kubectl apply -f $M/01-configmap.yaml"
run "kubectl get configmap"
echo
echo "--- describe shows the VALUES in plain text (they are not secret) ---"
run "kubectl describe configmap yatri-app-config"
echo
echo "--- read ONE key with jsonpath  [checklist 1] ---"
run "kubectl get configmap yatri-app-config -o jsonpath='{.data.DEFAULT_CURRENCY}{\"\\n\"}'"
run "kubectl get configmap yatri-app-config -o jsonpath='{.data.MAX_BOOKING_DAYS}{\"\\n\"}'"
echo
echo "--- the imperative equivalents (useful, but prefer files in git) ---"
echo "\$ kubectl create configmap demo --from-literal=KEY=value"
echo "\$ kubectl create configmap demo --from-file=./app.properties"
echo "\$ kubectl create configmap demo --from-env-file=./.env"

hr "3. CREATE THE SECRET  [checklist 2]"
run "cat $M/02-secret.yaml | tail -10"
run "kubectl apply -f $M/02-secret.yaml"
run "kubectl get secret yatri-db-secret"
echo ">> TYPE=Opaque means arbitrary user-defined key/value data."
echo
echo "--- describe HIDES the values ---"
run "kubectl describe secret yatri-db-secret"
echo ">> Only byte counts. This is why people assume Secrets are encrypted."

hr "4. BASE64 IS NOT ENCRYPTION  [checklist 2]"
echo "--- the stored value ---"
run "kubectl get secret yatri-db-secret -o jsonpath='{.data.POSTGRES_PASSWORD}{\"\\n\"}'"
echo
echo "--- decode it. Anyone with read access can do this. ---"
echo "\$ kubectl get secret yatri-db-secret -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 --decode"
kubectl get secret yatri-db-secret -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 --decode; echo
echo
run "kubectl get secret yatri-db-secret -o jsonpath='{.data.POSTGRES_USER}' | base64 --decode"
echo
cat <<'NOTE'

  >> Base64 is an ENCODING, not encryption. It exists so binary values
  >> (certificates, keys) can live inside YAML - not to hide anything.

  WHAT ACTUALLY PROTECTS A SECRET:
    - RBAC: control who can `get secrets` at all
    - encryption at rest: EncryptionConfiguration on the API server, so etcd
      does not hold plaintext
    - an external store: Vault, AWS/GCP Secrets Manager, Sealed Secrets
    - NEVER commit a real Secret manifest to git - the base64 is not a defence

NOTE

hr "5. THE echo vs echo -n NEWLINE BUG  [checklist 9]"
echo "--- WRONG: plain echo appends a trailing newline ---"
echo "\$ echo 'secretpassword' | base64"
WRONG=$(echo 'secretpassword' | base64)
echo "$WRONG"
echo
echo "--- RIGHT: -n suppresses it ---"
echo "\$ echo -n 'secretpassword' | base64"
RIGHT=$(echo -n 'secretpassword' | base64)
echo "$RIGHT"
echo
echo "--- the two encodings differ ---"
printf '  with newline : %s\n' "$WRONG"
printf '  without      : %s\n' "$RIGHT"
echo
echo "--- decode both and count the bytes ---"
echo "\$ echo '$WRONG' | base64 --decode | wc -c"
echo "$WRONG" | base64 --decode | wc -c
echo "\$ echo '$RIGHT' | base64 --decode | wc -c"
echo "$RIGHT" | base64 --decode | wc -c
echo
echo "--- show the invisible character ---"
echo "\$ echo '$WRONG' | base64 --decode | od -c | head -2"
echo "$WRONG" | base64 --decode | od -c | head -2
echo
cat <<'NOTE'
  >> 15 bytes vs 14. The extra \n is INSIDE the password.
  >> The app sends "secretpassword\n" to PostgreSQL, authentication fails, and
  >> the error says only "password authentication failed for user" - it never
  >> mentions a newline. People lose hours to this.
  >>
  >> ALWAYS use `echo -n`, or avoid the problem entirely:
  >>    kubectl create secret generic db --from-literal=PASSWORD='secretpassword'
  >> (--from-literal does the encoding for you, with no newline)
NOTE

hr "6. INJECT INTO THE BACKEND  [checklist 3]"
run "grep -A14 'envFrom:' $M/03-backend.yaml | head -18"
echo
cat <<'NOTE'
  TWO INJECTION STYLES ON ONE POD:

    envFrom: configMapRef   imports EVERY key in the ConfigMap as an env var.
                            Convenient, but you cannot see the variable names
                            by reading the Deployment.

    env: + secretKeyRef     imports ONE specific key, and lets you rename it.
                            Explicit, and the usual choice for secrets.
NOTE
run "kubectl apply -f $M/03-backend.yaml"
kubectl rollout status deployment/yatri-backend --timeout=300s
run "kubectl get pods -l app=yatri-backend"
echo
echo "--- verify the env vars INSIDE the pod  [checklist 3] ---"
POD=$(kubectl get pods -l app=yatri-backend -o jsonpath='{.items[0].metadata.name}')
run "kubectl exec $POD -- env | grep -E 'ENVIRONMENT|LOG_LEVEL|DEFAULT_CURRENCY|MAX_BOOKING_DAYS' | sort"
echo ">> ...from the ConfigMap via envFrom."
echo
run "kubectl exec $POD -- env | grep -E 'POSTGRES_' | sort"
echo ">> ...from the Secret via secretKeyRef - DECODED automatically."
echo ">> Note the pod sees the PLAINTEXT. Base64 is only the storage format."
echo
echo "--- and the password is exactly 14 bytes, so no newline bug here ---"
run "kubectl exec $POD -- sh -c 'printf \"%s\" \"\$POSTGRES_PASSWORD\" | wc -c'"

hr "7. DEPLOY THE FRONTEND  [checklist 4]"
run "kubectl apply -f $M/04-frontend.yaml"
kubectl rollout status deployment/yatri-frontend --timeout=300s
run "kubectl get pods -l app=yatri-frontend"
echo
echo "--- the ConfigMap mounted as a VOLUME becomes a FILE ---"
FPOD=$(kubectl get pods -l app=yatri-frontend -o jsonpath='{.items[0].metadata.name}')
run "kubectl exec $FPOD -- ls -l /usr/share/nginx/html/"
run "kubectl exec $FPOD -- head -4 /usr/share/nginx/html/index.html"
echo ">> Each KEY in the ConfigMap became a FILE named after that key."
echo
echo "--- both services are ClusterIP  [checklist 4] ---"
run "kubectl get svc yatri-backend-service yatri-frontend-service"
echo ">> ClusterIP: neither is reachable from outside. The Ingress will be the"
echo ">> single entry point - that is the whole point of part 2."
