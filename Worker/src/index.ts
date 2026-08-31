import type {
  ContextRequest,
  Env,
  ErrorCode,
  InstallationRequest,
  Runtime,
} from "./contracts";
import { AtomicCounter } from "./counter";
import {
  isUUID,
  issueInstallationToken,
  opaqueIdentifier,
  verifyInstallationToken,
} from "./crypto";
import { requestContextInsight } from "./upstream";

export { AtomicCounter };

const defaultRuntime: Runtime = {
  now: () => new Date(),
  fetch: (...arguments_) => fetch(...arguments_),
  log: (record) => console.log(JSON.stringify(record)),
};

export default {
  fetch(request: Request, env: Env, context: ExecutionContext): Promise<Response> {
    return handleRequest(request, env, context, defaultRuntime);
  },
};

export async function handleRequest(
  request: Request,
  env: Env,
  _context: Pick<ExecutionContext, "waitUntil">,
  runtime: Runtime = defaultRuntime,
): Promise<Response> {
  const started = performance.now();
  const url = new URL(request.url);
  let requestId: string = crypto.randomUUID();
  let status = 500;
  const route = knownRoute(url.pathname);
  let remaining: number | undefined;

  try {
    if (request.method === "GET" && url.pathname === "/health") {
      if (!validSecrets(env) || !validProductionIdentity(env)) {
        status = 503;
        return errorResponse("upstream_unavailable", 503);
      }
      status = 200;
      return json({ status: "ok" }, 200);
    }
    if (request.method === "GET" && url.pathname === "/version") {
      if (!validProductionIdentity(env)) {
        status = 503;
        return errorResponse("upstream_unavailable", 503);
      }
      status = 200;
      return json({
        version: env.PRODUCT_VERSION,
        commit: env.SOURCE_REVISION.toLowerCase(),
      }, 200);
    }
    if (request.method !== "POST") {
      status = 405;
      return errorResponse("invalid_request", 405);
    }

    if (url.pathname === "/v1/installations") {
      const response = await createInstallation(request, env, runtime);
      status = response.status;
      return response;
    }
    if (url.pathname === "/v1/context") {
      const parsed = await parseContextRequest(request);
      if (parsed && validContextRequest(parsed)) requestId = parsed.requestId;
      const response = await createContext(request, parsed, env, runtime);
      status = response.status;
      const quotaHeader = response.headers.get("x-quota-remaining");
      if (quotaHeader !== null) {
        const parsedQuota = Number(quotaHeader);
        if (Number.isInteger(parsedQuota) && parsedQuota >= 0) remaining = parsedQuota;
      }
      return response;
    }
    status = 404;
    return errorResponse("invalid_request", 404);
  } catch {
    status = 503;
    return errorResponse("upstream_unavailable", 503);
  } finally {
    runtime.log({
      requestId,
      route,
      durationMs: Math.round(performance.now() - started),
      status,
      ...(remaining === undefined ? {} : { remainingQuota: remaining }),
    });
  }
}

async function createInstallation(request: Request, env: Env, runtime: Runtime): Promise<Response> {
  if (!validSecrets(env)) return errorResponse("upstream_unavailable", 503);
  const body = await readJSON<InstallationRequest>(request);
  if (!body || Object.keys(body).length !== 0) {
    return errorResponse("invalid_request", 400);
  }

  const ip = clientIP(request);
  const window = hourKey(runtime.now());
  const allowed = await consume(env, `install:${await opaqueIdentifier(ip, env.INSTALLATION_SECRET)}:${window}`, 120);
  if (!allowed.allowed) return errorResponse("quota_exhausted", 429);

  const token = await issueInstallationToken(crypto.randomUUID(), env.INSTALLATION_SECRET, runtime.now());
  return json({ token }, 201);
}

async function createContext(
  request: Request,
  parsed: ContextRequest | null,
  env: Env,
  runtime: Runtime,
): Promise<Response> {
  if (!validSecrets(env)) return errorResponse("upstream_unavailable", 503);
  const bearer = request.headers.get("authorization")?.match(/^Bearer (\S+)$/)?.[1];
  if (!bearer) return errorResponse("unauthorized", 401);
  const installationId = await verifyWithActiveSecrets(bearer, env, runtime.now());
  if (!installationId) return errorResponse("unauthorized", 401);
  if (!parsed || !validContextRequest(parsed)) return errorResponse("invalid_request", 400);

  const ip = clientIP(request);
  const minute = minuteKey(runtime.now());
  const burst = await consume(env, `burst:${await opaqueIdentifier(ip, env.INSTALLATION_SECRET)}:${minute}`, 60);
  if (!burst.allowed) return errorResponse("quota_exhausted", 429);

  const day = utcDayKey(runtime.now());
  const installationHash = await opaqueIdentifier(installationId, env.INSTALLATION_SECRET);
  const quotaName = `quota:${installationHash}:${day}`;
  const quota = await consume(env, quotaName, 30);
  const resetAt = nextUTCMidnight(runtime.now()).toISOString();
  if (!quota.allowed) {
    return jsonError("quota_exhausted", 429, { resetAt });
  }

  const upstream = await requestContextInsight(parsed, env, runtime);
  if (!upstream.ok) {
    await refund(env, quotaName);
    return errorResponse(upstream.code, upstream.code === "timeout" ? 504 : 503);
  }

  const response = json(
    { insight: upstream.insight, remainingQuota: quota.remaining, resetAt },
    200,
  );
  response.headers.set("x-quota-remaining", String(quota.remaining));
  return response;
}

async function parseContextRequest(request: Request): Promise<ContextRequest | null> {
  return readJSON<ContextRequest>(request);
}

function validContextRequest(value: ContextRequest): boolean {
  if (!(
    isUUID(value.requestId) &&
    validText(value.word, 1, 100) &&
    validText(value.context, 0, 600) &&
    Number.isInteger(value.targetStart) &&
    value.targetStart >= 0 &&
    Number.isInteger(value.targetLength) &&
    value.targetLength > 0 &&
    value.targetStart + value.targetLength <= value.context.length &&
    ["en", "zh-Hans"].includes(value.sourceLanguage) &&
    ["en", "zh-Hans"].includes(value.targetLanguage) &&
    value.sourceLanguage !== value.targetLanguage
  )) return false;

  const selected = value.context.slice(value.targetStart, value.targetStart + value.targetLength);
  return value.sourceLanguage === "en"
    ? selected.toLocaleLowerCase("en-US") === value.word.toLocaleLowerCase("en-US")
    : selected === value.word;
}

function validText(value: unknown, minimum: number, maximum: number): value is string {
  if (typeof value !== "string") return false;
  const length = value.length;
  return length >= minimum && length <= maximum && value === value.trim();
}

function validSecrets(env: Env): boolean {
  return env.INSTALLATION_SECRET?.length >= 32 &&
    env.DEEPSEEK_API_KEY?.length >= 8 &&
    (!env.PREVIOUS_INSTALLATION_SECRET || env.PREVIOUS_INSTALLATION_SECRET.length >= 32);
}

async function verifyWithActiveSecrets(token: string, env: Env, now: Date): Promise<string | null> {
  const current = await verifyInstallationToken(token, env.INSTALLATION_SECRET, now);
  if (current || !env.PREVIOUS_INSTALLATION_SECRET) return current;
  return verifyInstallationToken(token, env.PREVIOUS_INSTALLATION_SECRET, now);
}

function knownRoute(pathname: string): string {
  switch (pathname) {
    case "/health":
    case "/version":
    case "/v1/installations":
    case "/v1/context":
      return pathname;
    default:
      return "unknown";
  }
}

function validProductionIdentity(env: Env): boolean {
  return /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/.test(env.PRODUCT_VERSION ?? "") &&
    /^[0-9a-f]{40}$/i.test(env.SOURCE_REVISION ?? "");
}

async function readJSON<T>(request: Request): Promise<T | null> {
  if (!request.headers.get("content-type")?.toLowerCase().startsWith("application/json")) return null;
  try {
    const text = await request.text();
    if (text.length > 4_096) return null;
    return JSON.parse(text) as T;
  } catch {
    return null;
  }
}

interface CounterResult {
  allowed: boolean;
  count: number;
  remaining: number;
}

async function consume(env: Env, name: string, limit: number): Promise<CounterResult> {
  const id = env.COUNTERS.idFromName(name);
  const response = await env.COUNTERS.get(id).fetch("https://counter/consume", {
    method: "POST",
    body: JSON.stringify({ limit }),
  });
  if (!response.ok) throw new Error("Counter unavailable");
  return response.json<CounterResult>();
}

async function refund(env: Env, name: string): Promise<void> {
  const id = env.COUNTERS.idFromName(name);
  await env.COUNTERS.get(id).fetch("https://counter/refund", { method: "POST" });
}

function clientIP(request: Request): string {
  return request.headers.get("cf-connecting-ip") ?? "unknown";
}

export function utcDayKey(date: Date): string {
  return date.toISOString().slice(0, 10);
}

export function nextUTCMidnight(date: Date): Date {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate() + 1));
}

function minuteKey(date: Date): string {
  return date.toISOString().slice(0, 16);
}

function hourKey(date: Date): string {
  return date.toISOString().slice(0, 13);
}

function errorResponse(code: ErrorCode, status: number): Response {
  return jsonError(code, status);
}

function jsonError(code: ErrorCode, status: number, details?: Record<string, unknown>): Response {
  return json({ error: { code, ...(details ? { details } : {}) } }, status);
}

function json(value: unknown, status: number): Response {
  return Response.json(value, {
    status,
    headers: {
      "cache-control": "no-store",
      "content-type": "application/json; charset=utf-8",
      "x-content-type-options": "nosniff",
    },
  });
}
