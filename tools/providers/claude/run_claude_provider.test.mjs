import test from "node:test";
import assert from "node:assert/strict";

import {
  classifyAnthropicHttpError,
  extractJsonObjectText,
  resolveTransport,
} from "./run_claude_provider.mjs";

test("resolveTransport prefers anthropic_api when API key is present in auto mode", () => {
  const originalApiKey = process.env.ANTHROPIC_API_KEY;
  process.env.ANTHROPIC_API_KEY = "test-key";
  try {
    assert.equal(resolveTransport({ transport: "auto" }), "anthropic_api");
  } finally {
    if (originalApiKey === undefined) {
      delete process.env.ANTHROPIC_API_KEY;
    } else {
      process.env.ANTHROPIC_API_KEY = originalApiKey;
    }
  }
});

test("resolveTransport falls back to claude_code_sdk when API key is absent", () => {
  const originalApiKey = process.env.ANTHROPIC_API_KEY;
  delete process.env.ANTHROPIC_API_KEY;
  try {
    assert.equal(resolveTransport({ transport: "auto" }), "claude_code_sdk");
  } finally {
    if (originalApiKey !== undefined) {
      process.env.ANTHROPIC_API_KEY = originalApiKey;
    }
  }
});

test("extractJsonObjectText strips markdown fences", () => {
  const text = "```json\n{\"decision\":\"micro\"}\n```";
  assert.equal(extractJsonObjectText(text), "{\"decision\":\"micro\"}");
});

test("classifyAnthropicHttpError maps auth and rate limit statuses", () => {
  assert.equal(classifyAnthropicHttpError(401), "auth_missing");
  assert.equal(classifyAnthropicHttpError(403), "auth_forbidden");
  assert.equal(classifyAnthropicHttpError(429), "provider_rate_limited");
  assert.equal(classifyAnthropicHttpError(503), "provider_unavailable");
});
