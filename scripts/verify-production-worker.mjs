#!/usr/bin/env node

const arguments_ = process.argv.slice(2);
const identityOnly = arguments_.includes("--identity-only");
const positional = arguments_.filter((value) => !value.startsWith("--"));
const baseURL = positional[0] ?? "https://pointrans-api.cuostudio.workers.dev";
const expectedVersion = process.env.POINTRANS_EXPECTED_VERSION;
const expectedCommit = process.env.POINTRANS_EXPECTED_COMMIT;
const requestId = crypto.randomUUID();

const healthResponse = await fetch(`${baseURL}/health`);
const healthBody = await healthResponse.json().catch(() => ({}));
if (healthResponse.status !== 200 || healthBody.status !== "ok") {
  throw new Error(`Health endpoint failed: HTTP ${healthResponse.status}`);
}

const versionResponse = await fetch(`${baseURL}/version`);
const versionBody = await versionResponse.json().catch(() => ({}));
if (
  versionResponse.status !== 200 ||
  typeof versionBody.version !== "string" ||
  !/^[0-9a-f]{40}$/.test(versionBody.commit ?? "") ||
  (expectedVersion && versionBody.version !== expectedVersion) ||
  (expectedCommit && versionBody.commit !== expectedCommit)
) {
  throw new Error(`Version endpoint returned an unexpected deployment identity: HTTP ${versionResponse.status}`);
}

console.log(`Health endpoint: ${healthResponse.status}`);
console.log(`Version endpoint: ${versionResponse.status}`);
console.log(`Product version: ${versionBody.version}`);
console.log(`Source revision: ${versionBody.commit}`);

if (identityOnly) process.exit(0);

const installationResponse = await fetch(`${baseURL}/v1/installations`, {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({}),
});

const installationBody = await installationResponse.json().catch(() => ({}));
if (installationResponse.status !== 201 || typeof installationBody.token !== "string") {
  throw new Error(`Installation endpoint failed: HTTP ${installationResponse.status}, code ${installationBody?.error?.code ?? "unknown"}`);
}

const contextResponse = await fetch(`${baseURL}/v1/context`, {
  method: "POST",
  headers: {
    authorization: `Bearer ${installationBody.token}`,
    "content-type": "application/json",
  },
  body: JSON.stringify({
    requestId,
    word: "pulling",
    context: "She kept pulling the rope until the knot came loose.",
    targetStart: 9,
    targetLength: 7,
    sourceLanguage: "en",
    targetLanguage: "zh-Hans",
  }),
});

const contextBody = await contextResponse.json().catch(() => ({}));
if (contextResponse.status !== 200) {
  throw new Error(`Context endpoint failed: HTTP ${contextResponse.status}, code ${contextBody?.error?.code ?? "unknown"}`);
}

const insight = contextBody.insight;
if (
  !insight ||
  typeof insight.contextualMeaning !== "string" ||
  typeof insight.explanation !== "string" ||
  !Number.isInteger(contextBody.remainingQuota) ||
  typeof contextBody.resetAt !== "string"
) {
  throw new Error("Context endpoint returned an invalid response contract");
}

console.log(`Installation endpoint: ${installationResponse.status}`);
console.log(`Context endpoint: ${contextResponse.status}`);
console.log(`ContextInsight contract: valid`);
console.log(`Remaining cloud quota: ${contextBody.remainingQuota}`);
console.log(`Quota reset: ${contextBody.resetAt}`);
