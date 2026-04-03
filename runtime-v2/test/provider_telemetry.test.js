"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  normalizeProviderTelemetryRecord,
  summarizeProviderTelemetry,
} = require("../src/provider_telemetry");

test("normalizeProviderTelemetryRecord returns canonical telemetry record", () => {
  const record = normalizeProviderTelemetryRecord({
    ts: "2026-04-02T10:00:00Z",
    requestId: "req-42",
    taskId: "ISSUE-622",
    module: "intake.interpretation",
    requestedProvider: "auto",
    effectiveProvider: "claude",
    outcome: "fallback",
    fallbackUsed: true,
    fallbackFromProvider: "claude",
    decisionReason: "auto_router_intake_ambiguous_or_reasoning_heavy",
    timeoutMs: 45000,
    budgetKey: "intake",
    errorClass: "schema_error",
    latencyMs: 1200,
    tokenUsage: 2400,
    estimatedCost: 0.08,
    misroute: false,
  });

  assert.equal(record.effectiveProvider, "claude");
  assert.equal(record.outcome, "fallback");
  assert.equal(record.fallbackUsed, true);
  assert.equal(record.errorClass, "schema_error");
  assert.equal(record.decisionReason, "auto_router_intake_ambiguous_or_reasoning_heavy");
});

test("summarizeProviderTelemetry aggregates canonical counters", () => {
  const summary = summarizeProviderTelemetry([
    {
      ts: "2026-04-02T10:00:00Z",
      requestId: "req-1",
      taskId: "ISSUE-622",
      module: "intake.interpretation",
      requestedProvider: "auto",
      effectiveProvider: "claude",
      outcome: "success",
      decisionReason: "configured_provider",
      latencyMs: 900,
    },
    {
      ts: "2026-04-02T10:00:02Z",
      requestId: "req-2",
      taskId: "ISSUE-622",
      module: "intake.ask_human",
      requestedProvider: "claude",
      effectiveProvider: "codex",
      outcome: "fallback",
      fallbackUsed: true,
      fallbackFromProvider: "claude",
      decisionReason: "auto_router_intake_ambiguous_or_reasoning_heavy",
      errorClass: "provider_timeout",
      latencyMs: 1500,
      misroute: true,
    },
  ]);

  assert.equal(summary.total, 2);
  assert.equal(summary.byProvider.claude, 1);
  assert.equal(summary.byProvider.codex, 1);
  assert.equal(summary.byOutcome.fallback, 1);
  assert.equal(summary.fallbackCount, 1);
  assert.equal(summary.misrouteCount, 1);
  assert.equal(summary.decisionReasonCounts.configured_provider, 1);
  assert.equal(summary.errorClassCounts.provider_timeout, 1);
});

test("normalizeProviderTelemetryRecord accepts local provider telemetry", () => {
  const record = normalizeProviderTelemetryRecord({
    ts: "2026-04-02T10:00:03Z",
    requestId: "req-local-2",
    taskId: "ISSUE-622",
    module: "intake.ask_human",
    requestedProvider: "local",
    effectiveProvider: "local",
    outcome: "success",
    decisionReason: "configured_provider",
    latencyMs: 15,
  });

  assert.equal(record.requestedProvider, "local");
  assert.equal(record.effectiveProvider, "local");
});

test("normalizeProviderTelemetryRecord accepts compare telemetry fields", () => {
  const record = normalizeProviderTelemetryRecord({
    ts: "2026-04-03T10:00:03Z",
    requestId: "req-compare-1",
    taskId: "ISSUE-622",
    module: "intake.interpretation",
    requestedProvider: "local",
    effectiveProvider: "claude",
    outcome: "error",
    compareMode: "dry_run",
    primaryProvider: "local",
    shadowProvider: "claude",
    schemaValidPrimary: true,
    schemaValidShadow: false,
    profileMatch: false,
    targetFilesMatch: false,
    humanNeededMatch: false,
    confidenceDelta: -0.4,
    compareSummary: "interpretation_profile_mismatch",
    publishDecision: false,
  });

  assert.equal(record.compareMode, "dry_run");
  assert.equal(record.schemaValidShadow, false);
  assert.equal(record.compareSummary, "interpretation_profile_mismatch");
});
