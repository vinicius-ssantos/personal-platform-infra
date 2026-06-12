type Env = {
  STATUS_TITLE?: string;
  CHECK_TIMEOUT_MS?: string;
  SERVICES_JSON?: string;
};

type Service = {
  name: string;
  url: string;
};

type ServiceStatus = Service & {
  ok: boolean;
  status: number | null;
  latencyMs: number;
  error?: string;
};

const DEFAULT_SERVICES: Service[] = [
  { name: "github-unified-mcp", url: "https://mcp-github.example.com/healthz" },
  { name: "deploy-orchestrator-mcp", url: "https://deploy-mcp.example.com/healthz" },
  { name: "mcp-social", url: "https://social-mcp.example.com/health" },
  { name: "github-unified-mcp-bff", url: "https://github-bff.example.com/healthz" },
  { name: "vos-studio-mcp", url: "https://vos-mcp.example.com/health" },
  { name: "vos-studio-bff", url: "https://vos-bff.example.com/healthz" },
];

const CACHE_TTL_SECONDS = 30;

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    // Non-GET methods bypass the cache (e.g. OPTIONS preflight).
    if (request.method !== "GET") {
      return serveRequest(url, env);
    }

    // Use the Cloudflare edge cache to avoid probing backend services on
    // every request. A burst of page views only triggers one probe round
    // per CACHE_TTL_SECONDS; backend services are protected from hammering.
    const cache = caches.default;
    const cacheKey = new Request(url.origin + url.pathname);
    const cached = await cache.match(cacheKey);
    if (cached) return cached;

    const response = await serveRequest(url, env);
    await cache.put(cacheKey, response.clone());
    return response;
  },
};

async function serveRequest(url: URL, env: Env): Promise<Response> {
  const services = parseServices(env.SERVICES_JSON);
  const timeoutMs = Number(env.CHECK_TIMEOUT_MS || "2500");
  const results = await Promise.all(services.map((service) => checkService(service, timeoutMs)));

  if (url.pathname === "/status.json") {
    return json({ ok: results.every((result) => result.ok), services: results });
  }

  return html(renderStatusPage(env.STATUS_TITLE || "Personal Platform", results));
}

function parseServices(raw: string | undefined): Service[] {
  if (!raw) {
    return DEFAULT_SERVICES;
  }

  try {
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) {
      return DEFAULT_SERVICES;
    }
    return parsed.filter((item): item is Service => {
      return typeof item?.name === "string" && typeof item?.url === "string";
    });
  } catch {
    return DEFAULT_SERVICES;
  }
}

async function checkService(service: Service, timeoutMs: number): Promise<ServiceStatus> {
  const startedAt = Date.now();
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort("timeout"), timeoutMs);

  try {
    const response = await fetch(service.url, {
      method: "GET",
      signal: controller.signal,
      headers: { "user-agent": "personal-platform-status/1.0" },
    });

    return {
      ...service,
      ok: response.ok,
      status: response.status,
      latencyMs: Date.now() - startedAt,
    };
  } catch (error) {
    return {
      ...service,
      ok: false,
      status: null,
      latencyMs: Date.now() - startedAt,
      error: error instanceof Error ? error.message : "request failed",
    };
  } finally {
    clearTimeout(timeout);
  }
}

function renderStatusPage(title: string, results: ServiceStatus[]): string {
  const allOk = results.every((result) => result.ok);
  const rows = results.map((result) => {
    const state = result.ok ? "ok" : "fail";
    const label = result.ok ? "OK" : "FAIL";
    const detail = result.error || `HTTP ${result.status}`;
    return `<tr>
      <td><strong>${escapeHtml(result.name)}</strong><br><span>${escapeHtml(result.url)}</span></td>
      <td><span class="badge ${state}">${label}</span></td>
      <td>${escapeHtml(detail)}</td>
      <td>${result.latencyMs} ms</td>
    </tr>`;
  }).join("");

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta http-equiv="refresh" content="30">
  <title>${escapeHtml(title)} Status</title>
  <style>
    :root { color-scheme: light dark; font-family: Inter, ui-sans-serif, system-ui, sans-serif; }
    body { margin: 0; padding: 32px; background: Canvas; color: CanvasText; }
    main { max-width: 960px; margin: 0 auto; }
    header { display: flex; align-items: end; justify-content: space-between; gap: 16px; margin-bottom: 24px; }
    h1 { font-size: 28px; margin: 0; }
    table { width: 100%; border-collapse: collapse; border: 1px solid color-mix(in srgb, CanvasText 18%, transparent); }
    th, td { padding: 14px 16px; border-bottom: 1px solid color-mix(in srgb, CanvasText 12%, transparent); text-align: left; }
    th { font-size: 12px; text-transform: uppercase; letter-spacing: .06em; }
    span { color: color-mix(in srgb, CanvasText 62%, transparent); font-size: 13px; }
    .badge { display: inline-block; min-width: 52px; padding: 4px 8px; border-radius: 4px; font-weight: 700; text-align: center; font-size: 12px; }
    .ok { background: #16794c; color: white; }
    .fail { background: #b42318; color: white; }
    .summary { font-weight: 700; color: ${allOk ? "#16794c" : "#b42318"}; }
  </style>
</head>
<body>
  <main>
    <header>
      <div>
        <h1>${escapeHtml(title)} Status</h1>
        <span>Auto-refresh every 30 seconds. JSON: /status.json</span>
      </div>
      <div class="summary">${allOk ? "All systems healthy" : "Service degradation"}</div>
    </header>
    <table>
      <thead><tr><th>Service</th><th>Status</th><th>Response</th><th>Latency</th></tr></thead>
      <tbody>${rows}</tbody>
    </table>
  </main>
</body>
</html>`;
}

function html(body: string): Response {
  return new Response(body, {
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": `public, max-age=${CACHE_TTL_SECONDS}`,
    },
  });
}

function json(body: unknown): Response {
  return new Response(JSON.stringify(body, null, 2), {
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": `public, max-age=${CACHE_TTL_SECONDS}`,
    },
  });
}

function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, (char) => {
    return ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;" } as Record<string, string>)[char];
  });
}
