// A Hello World web server for the Docker multi-stage build exercise.
//
// Go is used deliberately: it compiles to a single static binary, so the final
// image needs no compiler, no runtime and no OS packages at all. That makes the
// size difference between a single-stage and a multi-stage build about as stark
// as it gets (~880 MB vs ~12 MB).
package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"runtime"
	"time"
)

const message = "Hello World from Docker multi-stage build"

var startedAt = time.Now()

const style = `
:root{--bg:#0f1117;--card:#171a23;--line:#252a38;--fg:#e6e9f0;--muted:#8b93a7;--accent:#00add8}
*{margin:0;padding:0;box-sizing:border-box}
body{background:var(--bg);color:var(--fg);min-height:100vh;display:grid;place-items:center;
  font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;padding:24px}
.card{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:44px 52px;
  max-width:640px;width:100%;box-shadow:0 24px 60px rgba(0,0,0,.5)}
.badge{display:inline-flex;align-items:center;gap:8px;font-size:12px;font-weight:600;
  letter-spacing:.08em;text-transform:uppercase;color:var(--accent);
  background:rgba(0,173,216,.14);border:1px solid rgba(0,173,216,.3);
  padding:6px 12px;border-radius:999px;margin-bottom:22px}
h1{font-size:34px;line-height:1.2;letter-spacing:-.02em;margin-bottom:14px}
h1 span{color:var(--accent)}
.sub{color:var(--muted);font-size:15px;margin-bottom:28px}
dl{display:grid;grid-template-columns:auto 1fr;gap:10px 18px;font-size:14px;
  border-top:1px solid var(--line);padding-top:22px}
dt{color:var(--muted)}
dd{font-family:ui-monospace,'SF Mono',Menlo,monospace}
.foot{margin-top:24px;padding-top:18px;border-top:1px solid var(--line);color:var(--muted);font-size:13px}
`

func handler(w http.ResponseWriter, r *http.Request) {
	host, _ := os.Hostname()
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	fmt.Fprintf(w, `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Docker Multi-Stage Build</title>
  <style>%s</style>
</head>
<body>
  <div class="card">
    <div class="badge">● Multi-Stage Build</div>
    <h1>%s</h1>
    <p class="sub">A static Go binary in a scratch-based image &mdash; no compiler, no OS, no shell.</p>
    <dl>
      <dt>Language</dt><dd>%s</dd>
      <dt>Platform</dt><dd>%s / %s</dd>
      <dt>Container</dt><dd>%s</dd>
      <dt>Port</dt><dd>%s</dd>
      <dt>Uptime</dt><dd>%.1fs</dd>
    </dl>
    <p class="foot">Saswata Das &middot; 24BCS10248 &middot; DevOps Homework</p>
  </div>
</body>
</html>`, style, message, runtime.Version(), runtime.GOOS, runtime.GOARCH,
		host, port, time.Since(startedAt).Seconds())
}

func health(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	fmt.Fprint(w, `{"status":"ok","app":"multistage-app"}`)
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	http.HandleFunc("/", handler)
	http.HandleFunc("/health", health)

	log.Printf("multistage-app listening on http://0.0.0.0:%s", port)
	log.Printf("%s", message)
	if err := http.ListenAndServe("0.0.0.0:"+port, nil); err != nil {
		log.Fatal(err)
	}
}
