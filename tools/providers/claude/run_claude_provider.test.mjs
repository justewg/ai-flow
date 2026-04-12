import test from "node:test";
import assert from "node:assert/strict";

import {
  anthropicPricingForModel,
  classifyAnthropicHttpError,
  estimateAnthropicCostUsd,
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

test("estimateAnthropicCostUsd estimates Sonnet API usage cost", () => {
  assert.equal(
    estimateAnthropicCostUsd("claude-sonnet-4-5", {
      input_tokens: 1000,
      output_tokens: 100,
      cache_creation_input_tokens: 0,
      cache_read_input_tokens: 0,
    }),
    0.0045,
  );
});

test("estimateAnthropicCostUsd accounts for cache usage", () => {
  assert.equal(
    estimateAnthropicCostUsd("claude-haiku-4-5", {
      input_tokens: 1000,
      output_tokens: 100,
      cache_read_input_tokens: 1000,
      cache_creation: {
        ephemeral_5m_input_tokens: 1000,
        ephemeral_1h_input_tokens: 1000,
      },
    }),
    0.00485,
  );
});

test("anthropicPricingForModel allows env rate overrides", () => {
  const originalInput = process.env.CLAUDE_PROVIDER_INPUT_COST_PER_MTOK;
  const originalOutput = process.env.CLAUDE_PROVIDER_OUTPUT_COST_PER_MTOK;
  process.env.CLAUDE_PROVIDER_INPUT_COST_PER_MTOK = "2";
  process.env.CLAUDE_PROVIDER_OUTPUT_COST_PER_MTOK = "4";
  try {
    assert.deepEqual(anthropicPricingForModel("unknown-model"), {
      inputPerMTok: 2,
      outputPerMTok: 4,
      cacheWrite5mPerMTok: 2,
      cacheWrite1hPerMTok: 2,
      cacheReadPerMTok: 2,
      source: "env_override",
    });
  } finally {
    if (originalInput === undefined) {
      delete process.env.CLAUDE_PROVIDER_INPUT_COST_PER_MTOK;
    } else {
      process.env.CLAUDE_PROVIDER_INPUT_COST_PER_MTOK = originalInput;
    }
    if (originalOutput === undefined) {
      delete process.env.CLAUDE_PROVIDER_OUTPUT_COST_PER_MTOK;
    } else {
      process.env.CLAUDE_PROVIDER_OUTPUT_COST_PER_MTOK = originalOutput;
    }
  }
});
