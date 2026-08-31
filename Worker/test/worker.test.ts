import { beforeEach, describe, expect, it, vi } from "vitest";
import type { ContextInsight, Env, Runtime } from "../src/contracts";
import { AtomicCounter } from "../src/counter";
import { issueInstallationToken, verifyInstallationToken } from "../src/crypto";
import { handleRequest, nextUTCMidnight, utcDayKey } from "../src/index";

const SECRET = "installation-secret-with-at-least-32-bytes";
const API_KEY = "deepseek-test-key";
const INSTALLATION_ID = "2f9050b8-4fd6-4c48-84ec-12fc596b8c45";
const NOW = new Date("2026-08-25T12:30:00.000Z");

class FakeCounters {
  private readonly values = new Map<string, number>();

  idFromName(name: string): DurableObjectId {
    return { toString: () => name } as unknown as DurableObjectId;
  }

  get(id: DurableObjectId): DurableObjectStub {
    const name = id.toString();
    return {
      fetch: async (input: RequestInfo | URL, init?: RequestInit) => {
        const request = new Request(input, init);
        const path = new URL(request.url).pathname;
        const current = this.values.get(name) ?? 0;
        if (path === "/refund") {
          const next = Math.max(0, current - 1);
          this.values.set(name, next);
          return Response.json({ count: next });
        }
        const { limit } = (await request.json()) as { limit: number };
        if (current >= limit) return Response.json({ allowed: false, count: current, remaining: 0 });
        const next = current + 1;
        this.values.set(name, next);
        return Response.json({ allowed: true, count: next, remaining: limit - next });
      },
    } as unknown as DurableObjectStub;
  }
}

class FailingCounters {
  idFromName(name: string): DurableObjectId {
    return { toString: () => name } as unknown as DurableObjectId;
  }

  get(): DurableObjectStub {
    return {
      fetch: async () => { throw new Error("counter unavailable"); },
    } as unknown as DurableObjectStub;
  }
}

function insight(): ContextInsight {
  return {
    contextualMeaning: "持续拉扯",
    partOfSpeech: "verb",
    explanation: "The word describes continued pulling in this sentence.",
    contextTranslation: "她一直拉那根线。",
  };
}

function upstreamSuccess(): Response {
  return Response.json({
    output: [{
      type: "message",
      content: [{ type: "output_text", text: JSON.stringify(insight()) }],
    }],
  });
}

function makeRuntime(fetchImplementation: typeof fetch = vi.fn(async () => upstreamSuccess()) as typeof fetch) {
  const records: Array<Record<string, unknown>> = [];
  const runtime: Runtime = {
    now: () => new Date(NOW),
    fetch: fetchImplementation,
    log: (record) => records.push(record),
  };
  return { runtime, records };
}

function makeEnv(counters: FakeCounters | FailingCounters = new FakeCounters()): Env {
  return {
    COUNTERS: counters as unknown as DurableObjectNamespace,
    INSTALLATION_SECRET: SECRET,
    DEEPSEEK_API_KEY: API_KEY,
    SOURCE_REVISION: "0123456789abcdef0123456789abcdef01234567",
    PRODUCT_VERSION: "2.0.0",
  };
}

function executionContext(): Pick<ExecutionContext, "waitUntil"> {
  return { waitUntil: () => undefined };
}

function installationRequest(ip = "203.0.113.8", body: Record<string, unknown> = {}): Request {
  return new Request("https://pointrans.test/v1/installations", {
    method: "POST",
    headers: { "content-type": "application/json", "cf-connecting-ip": ip },
    body: JSON.stringify(body),
  });
}

function contextRequest(token: string, requestId: string = crypto.randomUUID(), overrides: Record<string, unknown> = {}): Request {
  return new Request("https://pointrans.test/v1/context", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "cf-connecting-ip": "203.0.113.8",
      authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({
      requestId,
      word: "pulling",
      context: "She kept pulling the thread.",
      targetStart: 9,
      targetLength: 7,
      sourceLanguage: "en",
      targetLanguage: "zh-Hans",
      ...overrides,
    }),
  });
}

async function install(env: Env, runtime: Runtime): Promise<string> {
  const response = await handleRequest(installationRequest(), env, executionContext(), runtime);
  expect(response.status).toBe(201);
  return ((await response.json()) as { token: string }).token;
}

describe("installation tokens", () => {
  it("issues an HMAC token and rejects tampering or expiry", async () => {
    const token = await issueInstallationToken(INSTALLATION_ID, SECRET, NOW);
    await expect(verifyInstallationToken(token, SECRET, NOW)).resolves.toBe(INSTALLATION_ID);
    await expect(verifyInstallationToken(`${token.slice(0, -1)}x`, SECRET, NOW)).resolves.toBeNull();
    await expect(
      verifyInstallationToken(token, SECRET, new Date("2027-09-01T00:00:00Z")),
    ).resolves.toBeNull();
  });

  it("rate limits token issuance by IP", async () => {
    const env = makeEnv();
    const { runtime } = makeRuntime();
    for (let index = 0; index < 120; index += 1) {
      expect((await handleRequest(installationRequest(), env, executionContext(), runtime)).status).toBe(201);
    }
    const denied = await handleRequest(
      installationRequest(),
      env,
      executionContext(),
      runtime,
    );
    expect(denied.status).toBe(429);
    await expect(denied.json()).resolves.toMatchObject({ error: { code: "quota_exhausted" } });
  });

  it("maps internal counter failures to the standard unavailable error", async () => {
    const env = makeEnv(new FailingCounters());
    const { runtime } = makeRuntime();
    const response = await handleRequest(installationRequest(), env, executionContext(), runtime);
    expect(response.status).toBe(503);
    await expect(response.json()).resolves.toMatchObject({ error: { code: "upstream_unavailable" } });
  });

  it("rejects client-supplied installation and application identity", async () => {
    const env = makeEnv();
    const { runtime } = makeRuntime();
    const response = await handleRequest(
      installationRequest("203.0.113.8", {
        installationId: INSTALLATION_ID,
        appVersion: "2.0.0",
      }),
      env,
      executionContext(),
      runtime,
    );
    expect(response.status).toBe(400);
  });

  it("accepts tokens signed by the previous secret during rotation", async () => {
    const previousSecret = "previous-installation-secret-at-least-32-bytes";
    const env = { ...makeEnv(), PREVIOUS_INSTALLATION_SECRET: previousSecret };
    const token = await issueInstallationToken(INSTALLATION_ID, previousSecret, NOW);
    const { runtime } = makeRuntime();

    const response = await handleRequest(contextRequest(token), env, executionContext(), runtime);
    expect(response.status).toBe(200);
  });
});

describe("production identity", () => {
  it("serves health and an exact product version plus full commit", async () => {
    const env = makeEnv();
    const { runtime } = makeRuntime();
    const health = await handleRequest(
      new Request("https://pointrans.test/health"),
      env,
      executionContext(),
      runtime,
    );
    expect(health.status).toBe(200);
    await expect(health.json()).resolves.toEqual({ status: "ok" });

    const version = await handleRequest(
      new Request("https://pointrans.test/version"),
      env,
      executionContext(),
      runtime,
    );
    expect(version.status).toBe(200);
    await expect(version.json()).resolves.toEqual({
      version: "2.0.0",
      commit: "0123456789abcdef0123456789abcdef01234567",
    });
  });

  it("fails closed when deployment identity is missing", async () => {
    const env = { ...makeEnv(), SOURCE_REVISION: "not-a-full-commit" };
    const { runtime } = makeRuntime();
    const response = await handleRequest(
      new Request("https://pointrans.test/version"),
      env,
      executionContext(),
      runtime,
    );
    expect(response.status).toBe(503);
    await expect(response.json()).resolves.toMatchObject({ error: { code: "upstream_unavailable" } });
  });

  it("fails health checks when required runtime secrets are invalid", async () => {
    const env = { ...makeEnv(), INSTALLATION_SECRET: "short" };
    const { runtime } = makeRuntime();
    const response = await handleRequest(
      new Request("https://pointrans.test/health"),
      env,
      executionContext(),
      runtime,
    );
    expect(response.status).toBe(503);
  });
});

describe("context endpoint", () => {
  it("uses DeepSeek Responses JSON schema and the production Flash model", async () => {
    let upstreamURL = "";
    let upstreamBody: Record<string, unknown> | undefined;
    const fetchMock = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      upstreamURL = String(input);
      upstreamBody = JSON.parse(String(init?.body)) as Record<string, unknown>;
      return upstreamSuccess();
    }) as typeof fetch;
    const env = makeEnv();
    const { runtime } = makeRuntime(fetchMock);
    const token = await install(env, runtime);

    expect((await handleRequest(contextRequest(token), env, executionContext(), runtime)).status).toBe(200);
    expect(upstreamURL).toBe("https://api.deepseek.com/responses");
    expect(upstreamBody).toMatchObject({
      model: "deepseek-v4-flash",
      reasoning: { effort: "none" },
      text: {
        format: {
          type: "json_schema",
          name: "context_insight",
          schema: {
            additionalProperties: false,
            required: [
              "contextualMeaning",
              "partOfSpeech",
              "explanation",
              "contextTranslation",
            ],
          },
        },
      },
    });
  });

  it("rejects malformed, oversized and unauthorized input", async () => {
    const env = makeEnv();
    const { runtime } = makeRuntime();
    const unauthorized = await handleRequest(contextRequest("bad-token"), env, executionContext(), runtime);
    expect(unauthorized.status).toBe(401);

    const token = await install(env, runtime);
    const oversized = await handleRequest(
      contextRequest(token, crypto.randomUUID(), { context: "x".repeat(601) }),
      env,
      executionContext(),
      runtime,
    );
    expect(oversized.status).toBe(400);
    await expect(oversized.json()).resolves.toMatchObject({ error: { code: "invalid_request" } });

    const mismatchedRange = await handleRequest(
      contextRequest(token, crypto.randomUUID(), { targetStart: 0, targetLength: 7 }),
      env,
      executionContext(),
      runtime,
    );
    expect(mismatchedRange.status).toBe(400);
  });

  it("never trusts an invalid client request ID in logs", async () => {
    const env = makeEnv();
    const { runtime, records } = makeRuntime();
    const token = await install(env, runtime);
    const response = await handleRequest(contextRequest(token, "forged-log-id"), env, executionContext(), runtime);

    expect(response.status).toBe(400);
    expect(records.at(-1)?.requestId).not.toBe("forged-log-id");
    expect(String(records.at(-1)?.requestId)).toMatch(/^[0-9a-f-]{36}$/);
  });

  it("enforces exactly 30 cloud requests per installation per UTC day", async () => {
    const env = makeEnv();
    const { runtime } = makeRuntime();
    const token = await install(env, runtime);
    for (let index = 0; index < 30; index += 1) {
      const response = await handleRequest(contextRequest(token), env, executionContext(), runtime);
      expect(response.status, `request ${index + 1}`).toBe(200);
      const payload = (await response.json()) as { remainingQuota: number };
      expect(payload.remainingQuota).toBe(29 - index);
    }
    const denied = await handleRequest(contextRequest(token), env, executionContext(), runtime);
    expect(denied.status).toBe(429);
    await expect(denied.json()).resolves.toMatchObject({ error: { code: "quota_exhausted" } });
  });

  it("rate limits burst traffic by IP across different installations", async () => {
    const env = makeEnv();
    const { runtime } = makeRuntime();
    const installationIds = [
      "2f9050b8-4fd6-4c48-84ec-100000000001",
      "2f9050b8-4fd6-4c48-84ec-100000000002",
      "2f9050b8-4fd6-4c48-84ec-100000000003",
      "2f9050b8-4fd6-4c48-84ec-100000000004",
    ];
    const tokens = await Promise.all(
      installationIds.map((id) => issueInstallationToken(id, SECRET, NOW)),
    );

    for (let index = 0; index < 60; index += 1) {
      const response = await handleRequest(
        contextRequest(tokens[index % tokens.length]!),
        env,
        executionContext(),
        runtime,
      );
      expect(response.status, `burst request ${index + 1}`).toBe(200);
    }

    const denied = await handleRequest(
      contextRequest(tokens[0]!),
      env,
      executionContext(),
      runtime,
    );
    expect(denied.status).toBe(429);
    await expect(denied.json()).resolves.toMatchObject({ error: { code: "quota_exhausted" } });
  });

  it("refunds quota when upstream returns 5xx", async () => {
    const env = makeEnv();
    let first = true;
    const fetchMock = vi.fn(async () => {
      if (first) {
        first = false;
        return new Response("unavailable", { status: 503 });
      }
      return upstreamSuccess();
    }) as typeof fetch;
    const { runtime } = makeRuntime(fetchMock);
    const token = await install(env, runtime);

    const failed = await handleRequest(contextRequest(token), env, executionContext(), runtime);
    expect(failed.status).toBe(503);
    for (let index = 0; index < 30; index += 1) {
      expect((await handleRequest(contextRequest(token), env, executionContext(), runtime)).status).toBe(200);
    }
    expect((await handleRequest(contextRequest(token), env, executionContext(), runtime)).status).toBe(429);
  });

  it("maps aborts to timeout and refunds the reservation", async () => {
    const env = makeEnv();
    const fetchMock = vi.fn(async () => {
      throw new DOMException("aborted", "AbortError");
    }) as typeof fetch;
    const { runtime } = makeRuntime(fetchMock);
    const token = await install(env, runtime);
    const response = await handleRequest(contextRequest(token), env, executionContext(), runtime);
    expect(response.status).toBe(504);
    await expect(response.json()).resolves.toMatchObject({ error: { code: "timeout" } });
  });

  it("never logs word, context, response body, or installation ID", async () => {
    const env = makeEnv();
    const { runtime, records } = makeRuntime();
    const token = await install(env, runtime);
    await handleRequest(
      contextRequest(token, crypto.randomUUID(), { word: "ultraSecretWord", context: "private sentence" }),
      env,
      executionContext(),
      runtime,
    );
    const log = JSON.stringify(records);
    expect(log).not.toContain("ultraSecretWord");
    expect(log).not.toContain("private sentence");
    expect(log).not.toContain("持续拉扯");
    expect(log).not.toContain(INSTALLATION_ID);
  });

  it("records a zero remaining quota without treating it as missing", async () => {
    const env = makeEnv();
    const { runtime, records } = makeRuntime();
    const token = await install(env, runtime);

    for (let index = 0; index < 30; index += 1) {
      expect((await handleRequest(contextRequest(token), env, executionContext(), runtime)).status).toBe(200);
    }

    expect(records.at(-1)).toMatchObject({
      status: 200,
      route: "/v1/context",
      remainingQuota: 0,
    });
  });
});

describe("counter and UTC reset", () => {
  it("uses UTC day boundaries", () => {
    const date = new Date("2026-12-31T23:59:59.999Z");
    expect(utcDayKey(date)).toBe("2026-12-31");
    expect(nextUTCMidnight(date).toISOString()).toBe("2027-01-01T00:00:00.000Z");
  });

  it("atomically refuses request 31 and supports refunds", async () => {
    let value = 0;
    const storage = {
      transaction: async <T>(body: (transaction: unknown) => Promise<T>) => body(storage),
      get: async () => value,
      put: async (_key: string, next: number) => { value = next; },
    };
    const counter = new AtomicCounter({ storage } as unknown as DurableObjectState);
    for (let index = 0; index < 30; index += 1) {
      const result = await counter.fetch(new Request("https://counter/consume", {
        method: "POST",
        body: JSON.stringify({ limit: 30 }),
      }));
      await expect(result.json()).resolves.toMatchObject({ allowed: true });
    }
    const denied = await counter.fetch(new Request("https://counter/consume", {
      method: "POST",
      body: JSON.stringify({ limit: 30 }),
    }));
    await expect(denied.json()).resolves.toMatchObject({ allowed: false, remaining: 0 });
    await counter.fetch(new Request("https://counter/refund", { method: "POST" }));
    const accepted = await counter.fetch(new Request("https://counter/consume", {
      method: "POST",
      body: JSON.stringify({ limit: 30 }),
    }));
    await expect(accepted.json()).resolves.toMatchObject({ allowed: true, remaining: 0 });
  });
});
