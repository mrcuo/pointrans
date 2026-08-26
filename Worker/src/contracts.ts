export interface ContextInsight {
  contextualMeaning: string;
  partOfSpeech?: string | null;
  explanation: string;
  contextTranslation?: string | null;
}

export interface InstallationRequest {
  installationId: string;
  appVersion: string;
}

export interface ContextRequest {
  requestId: string;
  word: string;
  context: string;
  sourceLanguage: "en" | "zh-Hans";
  targetLanguage: "en" | "zh-Hans";
}

export type ErrorCode =
  | "invalid_request"
  | "unauthorized"
  | "quota_exhausted"
  | "upstream_unavailable"
  | "timeout";

export interface Env {
  COUNTERS: DurableObjectNamespace;
  INSTALLATION_SECRET: string;
  DEEPSEEK_API_KEY: string;
  SOURCE_REVISION: string;
  PRODUCT_VERSION: string;
}

export interface Runtime {
  now: () => Date;
  fetch: typeof fetch;
  log: (record: Record<string, unknown>) => void;
}
