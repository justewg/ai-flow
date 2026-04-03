"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  normalizeProviderRequest,
  normalizeProviderResult,
} = require("../src/provider_contract");
const { ValidationError } = require("../src/errors");

test("normalizeProviderRequest returns canonical provider request", () => {
  const request = normalizeProviderRequest({
    requestId: "req-1",
    taskId: "ISSUE-622",
    issueNumber: 622,
    module: "intake.interpretation",
    preferredProvider: "claude",
    prompt: "interpret this task",
    input: { title: "test" },
    meta: { source: "intake" },
  });

  assert.equal(request.requestId, "req-1");
  assert.equal(request.taskId, "ISSUE-622");
  assert.equal(request.module, "intake.interpretation");
  assert.equal(request.preferredProvider, "claude");
  assert.equal(request.issueNumber, 622);
});

test("normalizeProviderResult returns canonical provider result", () => {
  const result = normalizeProviderResult({
    requestId: "req-1",
    taskId: "ISSUE-622",
    module: "intake.ask_human",
    provider: "codex",
    outcome: "success",
    outputText: "Need clarification",
    structuredOutput: { mode: "QUESTION" },
    latencyMs: 840,
    tokenUsage: 1200,
    estimatedCost: 0.03,
  });

  assert.equal(result.provider, "codex");
  assert.equal(result.outcome, "success");
  assert.equal(result.latencyMs, 840);
  assert.equal(result.tokenUsage, 1200);
});

test("normalizeProviderResult accepts local provider for deterministic modules", () => {
  const result = normalizeProviderResult({
    requestId: "req-local-1",
    taskId: "ISSUE-622",
    module: "intake.ask_human",
    provider: "local",
    outcome: "success",
    outputText: "Need clarification",
    structuredOutput: { mode: "QUESTION" },
  });

  assert.equal(result.provider, "local");
  assert.equal(result.outcome, "success");
});

test("normalizeProviderResult rejects unsupported provider", () => {
  assert.throws(
    () =>
      normalizeProviderResult({
        requestId: "req-1",
        taskId: "ISSUE-622",
        module: "intake.interpretation",
        provider: "unknown",
        outcome: "success",
      }),
    ValidationError,
  );
});
