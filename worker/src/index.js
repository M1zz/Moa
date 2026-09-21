/**
 * Moa relay — a short-lived mailbox between guests (App Clip) and the host app.
 *
 * Nothing is kept long-term: the host app deletes each item right after importing it
 * into Photos, and an R2 lifecycle rule should purge anything older than 30 days.
 *
 * R2 layout
 *   events/<eventId>/meta.json                         event metadata (+ hashed host token)
 *   events/<eventId>/items/<itemId>/<kind>             photo | pairedVideo | video
 *   events/<eventId>/items/<itemId>/manifest.json      written last; marks the item complete
 */

const ID_PATTERN = /^[A-Za-z0-9_-]{8,64}$/;
const RESOURCE_KINDS = new Set(["photo", "pairedVideo", "video"]);
const DAY_MS = 24 * 60 * 60 * 1000;
const LIST_LIMIT = 100;

export default {
  async fetch(request, env) {
    try {
      return await route(request, env);
    } catch (err) {
      console.error(err);
      return error(500, "서버에서 문제가 생겼어요.");
    }
  },
};

async function route(request, env) {
  const url = new URL(request.url);
  const parts = url.pathname.split("/").filter(Boolean);
  const method = request.method;

  if (url.pathname === "/.well-known/apple-app-site-association") return appSiteAssociation(env);
  if (parts[0] === "e" && parts.length === 2 && method === "GET") return landingPage(env, parts[1]);
  if (parts[0] !== "api" || parts[1] !== "events") return error(404, "Not found");

  // /api/events
  if (parts.length === 2 && method === "POST") return createEvent(request, env);

  // /api/events/:eventId
  const eventId = parts[2];
  if (!ID_PATTERN.test(eventId ?? "")) return error(404, "이벤트를 찾을 수 없어요.");
  if (parts.length === 3 && method === "GET") return getEvent(env, eventId);

  // /api/events/:eventId/items
  if (parts[3] !== "items") return error(404, "Not found");
  if (parts.length === 4 && method === "GET") return listItems(request, env, eventId);

  // /api/events/:eventId/items/:itemId[/...]
  const itemId = parts[4];
  if (!ID_PATTERN.test(itemId ?? "")) return error(400, "잘못된 항목 ID예요.");
  if (parts.length === 5 && method === "DELETE") return deleteItem(request, env, eventId, itemId);

  const tail = parts[5];
  if (parts.length === 6 && tail === "complete" && method === "POST") {
    return completeItem(request, env, eventId, itemId);
  }
  if (parts.length === 6 && RESOURCE_KINDS.has(tail)) {
    if (method === "PUT") return uploadResource(request, env, eventId, itemId, tail);
    if (method === "GET") return downloadResource(request, env, eventId, itemId, tail);
  }
  return error(404, "Not found");
}

// MARK: Events

async function createEvent(request, env) {
  const body = await readJSON(request);
  if (!body) return error(400, "요청 형식이 잘못됐어요.");

  const name = String(body.name ?? "").trim().slice(0, 60);
  if (!name) return error(400, "이벤트 이름이 필요해요.");
  const days = clamp(parseInt(body.days, 10) || 3, 1, 30);

  const id = randomId(12);
  const hostToken = randomId(32);
  const now = new Date();
  const meta = {
    id,
    name,
    createdAt: now.toISOString(),
    expiresAt: new Date(now.getTime() + days * DAY_MS).toISOString(),
    hostTokenHash: await sha256(hostToken),
  };
  await env.BUCKET.put(metaKey(id), JSON.stringify(meta), {
    httpMetadata: { contentType: "application/json" },
  });

  return json({ id, name, expiresAt: meta.expiresAt, hostToken }, 201);
}

async function getEvent(env, eventId) {
  const meta = await loadEvent(env, eventId);
  if (!meta) return error(404, "이벤트를 찾을 수 없어요.");
  if (isExpired(meta)) return error(410, "사진 받기가 종료된 이벤트예요.");
  return json({ id: meta.id, name: meta.name, expiresAt: meta.expiresAt });
}

// MARK: Guest uploads

async function uploadResource(request, env, eventId, itemId, kind) {
  const check = await requireOpenEvent(env, eventId);
  if (check.response) return check.response;

  const max = Number(env.MAX_UPLOAD_BYTES ?? 104857600);
  const length = Number(request.headers.get("content-length"));
  if (!Number.isFinite(length) || length <= 0) return error(411, "파일 크기 정보가 필요해요.");
  if (length > max) return error(413, `파일이 너무 커요. (최대 ${Math.floor(max / 1048576)}MB)`);
  if (await env.BUCKET.head(manifestKey(eventId, itemId))) return error(409, "이미 전송이 끝난 항목이에요.");

  const contentType = request.headers.get("content-type") ?? "application/octet-stream";
  await env.BUCKET.put(resourceKey(eventId, itemId, kind), request.body, {
    httpMetadata: { contentType },
  });
  return json({ ok: true });
}

async function completeItem(request, env, eventId, itemId) {
  const check = await requireOpenEvent(env, eventId);
  if (check.response) return check.response;

  const body = await readJSON(request);
  if (!body || !Array.isArray(body.resources) || body.resources.length === 0) {
    return error(400, "보낸 파일 목록이 비어 있어요.");
  }

  const resources = [];
  const seen = new Set();
  for (const entry of body.resources.slice(0, RESOURCE_KINDS.size)) {
    const kind = entry?.kind;
    if (!RESOURCE_KINDS.has(kind) || seen.has(kind)) return error(400, "잘못된 파일 종류예요.");
    seen.add(kind);
    const head = await env.BUCKET.head(resourceKey(eventId, itemId, kind));
    if (!head) return error(400, `아직 올라오지 않은 파일이 있어요: ${kind}`);
    resources.push({
      kind,
      filename: String(entry.filename ?? kind).slice(0, 200),
      contentType: head.httpMetadata?.contentType ?? "application/octet-stream",
      size: head.size,
    });
  }

  const uploader = typeof body.uploader === "string" ? body.uploader.trim().slice(0, 40) : "";
  const manifest = {
    itemID: itemId,
    uploader: uploader || null,
    capturedAt: toISODate(body.capturedAt),
    resources,
    uploadedAt: new Date().toISOString(),
  };
  await env.BUCKET.put(manifestKey(eventId, itemId), JSON.stringify(manifest), {
    httpMetadata: { contentType: "application/json" },
  });
  return json({ ok: true }, 201);
}

// MARK: Host

async function listItems(request, env, eventId) {
  const auth = await requireHost(request, env, eventId);
  if (auth.response) return auth.response;

  const keys = [];
  let cursor;
  do {
    const page = await env.BUCKET.list({ prefix: `events/${eventId}/items/`, cursor });
    for (const object of page.objects) {
      if (object.key.endsWith("/manifest.json")) keys.push(object.key);
    }
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor && keys.length < LIST_LIMIT);

  const manifests = await Promise.all(
    keys.slice(0, LIST_LIMIT).map(async (key) => {
      const object = await env.BUCKET.get(key);
      return object ? object.json() : null;
    }),
  );
  const items = manifests
    .filter(Boolean)
    .sort((a, b) => String(a.uploadedAt).localeCompare(String(b.uploadedAt)));
  return json({ items });
}

async function downloadResource(request, env, eventId, itemId, kind) {
  const auth = await requireHost(request, env, eventId);
  if (auth.response) return auth.response;

  const object = await env.BUCKET.get(resourceKey(eventId, itemId, kind));
  if (!object) return error(404, "파일을 찾을 수 없어요.");
  return new Response(object.body, {
    headers: {
      "content-type": object.httpMetadata?.contentType ?? "application/octet-stream",
      "content-length": String(object.size),
      "cache-control": "no-store",
    },
  });
}

async function deleteItem(request, env, eventId, itemId) {
  const auth = await requireHost(request, env, eventId);
  if (auth.response) return auth.response;

  const listing = await env.BUCKET.list({ prefix: itemPrefix(eventId, itemId) });
  const keys = listing.objects.map((object) => object.key);
  if (keys.length > 0) await env.BUCKET.delete(keys);
  return json({ ok: true, deleted: keys.length });
}

// MARK: App Clip plumbing

function appSiteAssociation(env) {
  const body = { appclips: { apps: [`${env.TEAM_ID}.${env.CLIP_BUNDLE_ID}`] } };
  return new Response(JSON.stringify(body), {
    headers: { "content-type": "application/json" },
  });
}

/** Shown when the QR is opened somewhere the App Clip can't launch (desktop, Android, old iOS). */
async function landingPage(env, eventId) {
  const meta = ID_PATTERN.test(eventId) ? await loadEvent(env, eventId) : null;
  const title = meta ? meta.name : "모아";
  const status = !meta
    ? "이벤트를 찾을 수 없어요."
    : isExpired(meta)
      ? "사진 받기가 종료된 이벤트예요."
      : "iPhone 카메라로 QR을 스캔하면 앱 설치 없이 사진을 보낼 수 있어요.";

  const banner = [
    env.APP_STORE_ID ? `app-id=${env.APP_STORE_ID}` : null,
    `app-clip-bundle-id=${env.CLIP_BUNDLE_ID}`,
    "app-clip-display=card",
  ].filter(Boolean).join(", ");

  const html = `<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="apple-itunes-app" content="${escapeHTML(banner)}">
<title>${escapeHTML(title)} · 모아</title>
<style>
  :root { --ink: #10323a; --muted: #5b6f73; --bg: #f3f6f5; --accent: #14606e; }
  @media (prefers-color-scheme: dark) { :root { --ink: #e8f0ef; --muted: #9fb2b4; --bg: #0d1a1d; --accent: #6fc2cc; } }
  * { box-sizing: border-box; }
  body { margin: 0; min-height: 100dvh; display: grid; place-items: center; background: var(--bg); color: var(--ink);
         font: 17px/1.55 -apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", "Noto Sans KR", sans-serif;
         padding: env(safe-area-inset-top, 0px) 24px env(safe-area-inset-bottom, 0px); }
  main { max-width: 26rem; text-align: center; }
  .mark { width: 72px; height: 72px; border-radius: 18px; margin: 0 auto 20px; background: linear-gradient(#14606e, #f08a5d); }
  h1 { font-size: 1.6rem; line-height: 1.25; margin: 0 0 12px; word-break: keep-all; }
  p { color: var(--muted); margin: 0; word-break: keep-all; }
</style>
</head>
<body>
<main>
  <div class="mark" aria-hidden="true"></div>
  <h1>${escapeHTML(title)}</h1>
  <p>${escapeHTML(status)}</p>
</main>
</body>
</html>`;
  return new Response(html, {
    status: meta ? 200 : 404,
    headers: { "content-type": "text/html; charset=utf-8" },
  });
}

// MARK: Guards

async function requireOpenEvent(env, eventId) {
  const meta = await loadEvent(env, eventId);
  if (!meta) return { response: error(404, "이벤트를 찾을 수 없어요.") };
  if (isExpired(meta)) return { response: error(410, "사진 받기가 종료된 이벤트예요.") };
  return { meta };
}

/** Host endpoints stay usable after expiry so late imports still work. */
async function requireHost(request, env, eventId) {
  const meta = await loadEvent(env, eventId);
  if (!meta) return { response: error(404, "이벤트를 찾을 수 없어요.") };
  const header = request.headers.get("authorization") ?? "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : "";
  if (!token || (await sha256(token)) !== meta.hostTokenHash) {
    return { response: error(401, "권한이 없어요.") };
  }
  return { meta };
}

// MARK: Helpers

const metaKey = (eventId) => `events/${eventId}/meta.json`;
const itemPrefix = (eventId, itemId) => `events/${eventId}/items/${itemId}/`;
const resourceKey = (eventId, itemId, kind) => `${itemPrefix(eventId, itemId)}${kind}`;
const manifestKey = (eventId, itemId) => `${itemPrefix(eventId, itemId)}manifest.json`;

async function loadEvent(env, eventId) {
  const object = await env.BUCKET.get(metaKey(eventId));
  return object ? object.json() : null;
}

function isExpired(meta) {
  return Date.parse(meta.expiresAt) < Date.now();
}

async function readJSON(request) {
  try {
    return await request.json();
  } catch {
    return null;
  }
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
}

function error(status, message) {
  return json({ error: message }, status);
}

function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max);
}

function toISODate(value) {
  if (typeof value !== "string") return null;
  const time = Date.parse(value);
  return Number.isNaN(time) ? null : new Date(time).toISOString();
}

function randomId(byteLength) {
  const bytes = new Uint8Array(byteLength);
  crypto.getRandomValues(bytes);
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function sha256(text) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function escapeHTML(value) {
  return String(value).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
}
