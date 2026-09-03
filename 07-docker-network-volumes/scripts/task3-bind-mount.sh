#!/usr/bin/env bash
# Task 3: bind mount a local folder into an Nginx container and prove that
# edits on the host appear immediately, with NO container restart.
set -u
hr(){ echo; echo "==================== $* ===================="; }

BASE="$(cd "$(dirname "$0")/.." && pwd)"
SITE="$BASE/bind-mount-site"

docker rm -f nginx-bind nginx-copy >/dev/null 2>&1

hr "1. CREATE A FOLDER ON THE LOCAL MACHINE"
rm -rf "$SITE"; mkdir -p "$SITE"
echo "\$ mkdir -p $SITE"
ls -ld "$SITE"

hr "2. CREATE index.html WITH THE CONTENT 'Hello students'"
cat > "$SITE/index.html" <<HTML
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Bind Mount Demo</title>
  <style>
    :root{--bg:#0f1117;--card:#171a23;--line:#252a38;--fg:#e6e9f0;--muted:#8b93a7;--accent:#00b04f}
    *{margin:0;padding:0;box-sizing:border-box}
    body{background:var(--bg);color:var(--fg);min-height:100vh;display:grid;place-items:center;
      font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;padding:24px}
    .card{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:44px 52px;
      max-width:620px;width:100%;box-shadow:0 24px 60px rgba(0,0,0,.5)}
    .badge{display:inline-block;font-size:12px;font-weight:600;letter-spacing:.08em;
      text-transform:uppercase;color:var(--accent);background:rgba(0,176,79,.14);border:1px solid rgba(0,176,79,.3);
      padding:6px 12px;border-radius:999px;margin-bottom:22px}
    h1{font-size:38px;line-height:1.15;letter-spacing:-.02em;margin-bottom:12px}
    p{color:var(--muted);font-size:15px;line-height:1.6}
    code{font-family:ui-monospace,'SF Mono',Menlo,monospace;color:var(--accent);font-size:13.5px}
    .foot{margin-top:26px;padding-top:18px;border-top:1px solid var(--line);font-size:13px}
  </style>
</head>
<body>
  <div class="card">
    <div class="badge">Bind Mount &middot; original</div>
    <h1>Hello students</h1>
    <p>This file lives on the HOST at <code>bind-mount-site/index.html</code> and is
       bind-mounted into the Nginx container at <code>/usr/share/nginx/html</code>.</p>
    <p class="foot">Saswata Das &middot; 24BCS10248 &middot; DevOps Homework</p>
  </div>
</body>
</html>
HTML
echo "\$ cat $SITE/index.html"
cat "$SITE/index.html"

hr "3. BIND MOUNT THE FOLDER INTO AN NGINX CONTAINER"
echo "\$ docker run -d --name nginx-bind -p 8083:80 \\"
echo "      -v $SITE:/usr/share/nginx/html:ro nginx:alpine"
docker run -d --name nginx-bind -p 8083:80 \
  -v "$SITE":/usr/share/nginx/html:ro nginx:alpine
sleep 2
echo
echo "--- the mount, as Docker sees it ---"
echo "\$ docker inspect nginx-bind --format '{{range .Mounts}}...{{end}}'"
docker inspect nginx-bind --format '{{range .Mounts}}type={{.Type}}{{println}}source={{.Source}}{{println}}dest={{.Destination}}{{println}}readonly={{if .RW}}false{{else}}true{{end}}{{end}}'

hr "4. ACCESS THE NGINX WEBSITE AND VERIFY THE CONTENT"
echo "\$ curl -s http://localhost:8083/"
curl -s http://localhost:8083/
echo
echo "\$ curl -s http://localhost:8083/ | grep -o 'Hello students'"
curl -s http://localhost:8083/ | grep -o 'Hello students'
echo ">> The container is serving the file straight off the host filesystem."
echo
echo "--- the same file, seen from INSIDE the container ---"
echo "\$ docker exec nginx-bind cat /usr/share/nginx/html/index.html"
docker exec nginx-bind cat /usr/share/nginx/html/index.html
echo "\$ docker exec nginx-bind ls -la /usr/share/nginx/html/"
docker exec nginx-bind ls -la /usr/share/nginx/html/

hr "5. MODIFY index.html ON THE HOST"
UPTIME_BEFORE=$(docker inspect nginx-bind --format '{{.State.StartedAt}}')
echo "container StartedAt BEFORE the edit : $UPTIME_BEFORE"
echo
cat > "$SITE/index.html" <<HTML
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Bind Mount Demo &mdash; edited</title>
  <style>
    :root{--bg:#0f1117;--card:#171a23;--line:#252a38;--fg:#e6e9f0;--muted:#8b93a7;--accent:#ffb020}
    *{margin:0;padding:0;box-sizing:border-box}
    body{background:var(--bg);color:var(--fg);min-height:100vh;display:grid;place-items:center;
      font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;padding:24px}
    .card{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:44px 52px;
      max-width:620px;width:100%;box-shadow:0 24px 60px rgba(0,0,0,.5)}
    .badge{display:inline-block;font-size:12px;font-weight:600;letter-spacing:.08em;
      text-transform:uppercase;color:var(--accent);background:rgba(255,176,32,.14);border:1px solid rgba(255,176,32,.3);
      padding:6px 12px;border-radius:999px;margin-bottom:22px}
    h1{font-size:38px;line-height:1.15;letter-spacing:-.02em;margin-bottom:12px}
    p{color:var(--muted);font-size:15px;line-height:1.6}
    code{font-family:ui-monospace,'SF Mono',Menlo,monospace;color:var(--accent);font-size:13.5px}
    .foot{margin-top:26px;padding-top:18px;border-top:1px solid var(--line);font-size:13px}
  </style>
</head>
<body>
  <div class="card">
    <div class="badge">Bind Mount &middot; edited live</div>
    <h1>Hello students &mdash; this file was EDITED on the host</h1>
    <p>The container was <strong>never restarted</strong>. No rebuild, no
       <code>docker cp</code>. The edit was made with a text editor on the host and
       the very next request served the new bytes.</p>
    <p class="foot">Saswata Das &middot; 24BCS10248 &middot; DevOps Homework</p>
  </div>
</body>
</html>
HTML
echo "\$ cat > $SITE/index.html   (edited on the host)"
cat "$SITE/index.html"
# Give the write a moment to settle. Because the mount is LIVE, an immediate
# request can otherwise catch the file mid-write and serve a truncated page --
# a real (if rarely mentioned) consequence of there being no copy step.
sync 2>/dev/null || true
sleep 1

hr "6. VERIFY THE CHANGE IS REFLECTED — WITHOUT RESTARTING"
echo "\$ curl -s http://localhost:8083/"
curl -s http://localhost:8083/
echo
echo "\$ curl -s http://localhost:8083/ | grep -o 'EDITED on the host'"
curl -s http://localhost:8083/ | grep -o 'EDITED on the host'
echo
UPTIME_AFTER=$(docker inspect nginx-bind --format '{{.State.StartedAt}}')
echo "container StartedAt AFTER the edit  : $UPTIME_AFTER"
if [ "$UPTIME_BEFORE" = "$UPTIME_AFTER" ]; then
  echo ">> IDENTICAL StartedAt — the container was NEVER restarted."
else
  echo ">> StartedAt changed — the container restarted (this should not happen)."
fi
echo
echo "\$ docker ps --filter name=nginx-bind"
docker ps --filter name=nginx-bind --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

hr "7. ADD A WHOLE NEW FILE ON THE HOST — it appears instantly too"
echo "<h1>A page created on the host after the container started</h1>" > "$SITE/new-page.html"
echo "\$ echo '...' > $SITE/new-page.html"
echo "\$ curl -s http://localhost:8083/new-page.html"
curl -s http://localhost:8083/new-page.html
echo "\$ docker exec nginx-bind ls /usr/share/nginx/html/"
docker exec nginx-bind ls /usr/share/nginx/html/

hr "8. THE :ro FLAG — the container CANNOT write back"
echo "\$ docker exec nginx-bind sh -c 'echo hacked > /usr/share/nginx/html/index.html'"
docker exec nginx-bind sh -c 'echo hacked > /usr/share/nginx/html/index.html' 2>&1 | head -2
echo ">> Read-only mount rejected the write. The host file is untouched:"
echo "\$ grep -o 'EDITED on the host' $SITE/index.html"
grep -o 'EDITED on the host' "$SITE/index.html"

hr "9. CONTRAST: a container WITHOUT the bind mount does not see the edits"
echo "\$ docker run -d --name nginx-copy -p 8084:80 nginx:alpine   (stock image, no mount)"
docker run -d --name nginx-copy -p 8084:80 nginx:alpine >/dev/null
sleep 2
echo "\$ curl -s http://localhost:8084/ | head -5"
curl -s http://localhost:8084/ | head -5
echo ">> The stock nginx welcome page — it has no idea our folder exists."
docker rm -f nginx-copy >/dev/null 2>&1

hr "10. BIND MOUNT vs NAMED VOLUME"
cat <<'NOTE'

                    | bind mount (-v /host/path:/ctr/path) | named volume (-v mydata:/ctr/path)
  ------------------|--------------------------------------|-----------------------------------
  Where it lives    | a path YOU choose on the host        | Docker-managed area
  Host can edit it  | yes, with any editor                 | awkward (inside Docker's storage)
  Portable          | no - depends on the host path         | yes - Docker creates it anywhere
  Best for          | DEVELOPMENT: live source reloading,   | PRODUCTION DATA: database files,
                    | config files, static site content     | uploads, anything that must persist
  Backup            | ordinary file copy                   | docker volume commands
  Created if absent | yes (as an empty DIRECTORY - a very  | yes, as a proper volume
                    | common cause of "file not found")    |

  WHY THE LIVE UPDATE WORKS: a bind mount is not a copy. The kernel mounts the
  host directory into the container's mount namespace, so both names refer to
  the SAME inodes on the SAME filesystem. There is nothing to synchronise -
  reading the file in the container reads the host's file.

NOTE
