const encoder = new TextEncoder();

interface TokenPayload {
  sub: string;
  iat: number;
  exp: number;
  v: 1;
}

export async function issueInstallationToken(
  installationId: string,
  secret: string,
  now: Date,
): Promise<string> {
  const issuedAt = Math.floor(now.getTime() / 1000);
  const payload: TokenPayload = {
    sub: installationId,
    iat: issuedAt,
    exp: issuedAt + 365 * 24 * 60 * 60,
    v: 1,
  };
  const encodedPayload = base64url(encoder.encode(JSON.stringify(payload)));
  const signature = await hmac(`v1.${encodedPayload}`, secret);
  return `v1.${encodedPayload}.${signature}`;
}

export async function verifyInstallationToken(
  token: string,
  secret: string,
  now: Date,
): Promise<string | null> {
  const [version, payloadPart, signature, extra] = token.split(".");
  if (version !== "v1" || !payloadPart || !signature || extra !== undefined) return null;
  const expected = await hmac(`v1.${payloadPart}`, secret);
  if (!timingSafeEqual(signature, expected)) return null;

  try {
    const payload = JSON.parse(new TextDecoder().decode(fromBase64url(payloadPart))) as TokenPayload;
    const nowSeconds = Math.floor(now.getTime() / 1000);
    if (payload.v !== 1 || !isUUID(payload.sub) || payload.iat > nowSeconds + 300 || payload.exp <= nowSeconds) {
      return null;
    }
    return payload.sub;
  } catch {
    return null;
  }
}

export async function opaqueIdentifier(value: string, secret: string): Promise<string> {
  return (await hmac(value, secret)).slice(0, 32);
}

export function isUUID(value: unknown): value is string {
  return typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

async function hmac(value: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(value));
  return base64url(new Uint8Array(signature));
}

function timingSafeEqual(lhs: string, rhs: string): boolean {
  const a = encoder.encode(lhs);
  const b = encoder.encode(rhs);
  let mismatch = a.length ^ b.length;
  const length = Math.max(a.length, b.length);
  for (let index = 0; index < length; index += 1) {
    mismatch |= (a[index % a.length] ?? 0) ^ (b[index % b.length] ?? 0);
  }
  return mismatch === 0;
}

function base64url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

function fromBase64url(value: string): Uint8Array {
  const normalized = value.replaceAll("-", "+").replaceAll("_", "/");
  const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=");
  const binary = atob(padded);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}
