import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.Executors;

/**
 * Hello World web application in Java.
 *
 * Uses the JDK's built-in com.sun.net.httpserver rather than Spring Boot, so the
 * app has zero external dependencies. That keeps the Docker build fast and
 * hermetic (no Maven Central download at build time) while still being a real
 * HTTP server.
 */
public class HelloWorld {

    private static final String STYLE = """
        :root{--bg:#0f1117;--card:#171a23;--line:#252a38;--fg:#e6e9f0;--muted:#8b93a7;--accent:#f89820}
        *{margin:0;padding:0;box-sizing:border-box}
        body{background:var(--bg);color:var(--fg);min-height:100vh;display:grid;place-items:center;
          font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;padding:24px}
        .card{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:44px 52px;
          max-width:560px;width:100%;box-shadow:0 24px 60px rgba(0,0,0,.5)}
        .badge{display:inline-flex;align-items:center;gap:8px;font-size:12px;font-weight:600;
          letter-spacing:.08em;text-transform:uppercase;color:var(--accent);
          background:rgba(248,152,32,.14);border:1px solid rgba(248,152,32,.3);
          padding:6px 12px;border-radius:999px;margin-bottom:22px}
        h1{font-size:44px;line-height:1.1;letter-spacing:-.02em;margin-bottom:10px}
        h1 span{color:var(--accent)}
        .sub{color:var(--muted);font-size:15px;margin-bottom:28px}
        dl{display:grid;grid-template-columns:auto 1fr;gap:10px 18px;font-size:14px;
          border-top:1px solid var(--line);padding-top:22px}
        dt{color:var(--muted)}
        dd{font-family:ui-monospace,'SF Mono',Menlo,monospace}
        .foot{margin-top:24px;padding-top:18px;border-top:1px solid var(--line);color:var(--muted);font-size:13px}
        """;

    public static void main(String[] args) throws IOException {
        int port = Integer.parseInt(System.getenv().getOrDefault("PORT", "8080"));

        HttpServer server = HttpServer.create(new InetSocketAddress("0.0.0.0", port), 0);
        server.createContext("/", HelloWorld::handleRoot);
        server.createContext("/health", HelloWorld::handleHealth);
        server.setExecutor(Executors.newFixedThreadPool(4));
        server.start();

        System.out.println("java-app listening on http://0.0.0.0:" + port);
    }

    private static void handleRoot(HttpExchange exchange) throws IOException {
        String host;
        try {
            host = InetAddress.getLocalHost().getHostName();
        } catch (Exception e) {
            host = "unknown";
        }

        String body = """
            <!doctype html>
            <html lang="en">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width,initial-scale=1">
              <title>Hello World — Java</title>
              <style>%s</style>
            </head>
            <body>
              <div class="card">
                <div class="badge">● Java</div>
                <h1>Hello <span>World</span></h1>
                <p class="sub">Served by a Java HTTP server running inside a Docker container.</p>
                <dl>
                  <dt>Runtime</dt><dd>Java %s</dd>
                  <dt>JVM</dt><dd>%s</dd>
                  <dt>Platform</dt><dd>%s / %s</dd>
                  <dt>Container</dt><dd>%s</dd>
                  <dt>Port</dt><dd>%s</dd>
                </dl>
                <p class="foot">Saswata Das &middot; 24BCS10248 &middot; DevOps Homework</p>
              </div>
            </body>
            </html>
            """.formatted(
                STYLE,
                System.getProperty("java.version"),
                System.getProperty("java.vm.name"),
                System.getProperty("os.name"),
                System.getProperty("os.arch"),
                host,
                System.getenv().getOrDefault("PORT", "8080"));

        send(exchange, 200, "text/html; charset=utf-8", body);
    }

    private static void handleHealth(HttpExchange exchange) throws IOException {
        send(exchange, 200, "application/json", "{\"status\":\"ok\",\"app\":\"java-app\"}");
    }

    private static void send(HttpExchange ex, int code, String type, String body) throws IOException {
        byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
        ex.getResponseHeaders().set("Content-Type", type);
        ex.sendResponseHeaders(code, bytes.length);
        try (OutputStream os = ex.getResponseBody()) {
            os.write(bytes);
        }
    }
}
