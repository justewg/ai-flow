"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const { evaluateProviderRolloutGate } = require("../src/provider_rollout_gate");

test("evaluateProviderRolloutGate blocks on insufficient samples and mismatch rate", () => {
  const summary = evaluateProviderRolloutGate(
    [
      {
        ts: "2026-04-03T00:00:00Z",
        requestId: "1",
        taskId: "ISSUE-1",
        module: "intake.interpretation",
        requestedProvider: "claude",
        effectiveProvider: "claude",
        outcome: "success",
        compareMode: "dry_run",
        primaryProvider: "local",
        shadowProvider: "claude",
        schemaValidShadow: true,
        profileMatch: false,
      },
    ],
    { module: "intake.interpretation", minSamples: 2 },
  );

  assert.equal(summary.ready, false);
  assert.match(summary.blockingReasons.join(","), /insufficient_samples/);
  assert.match(summary.blockingReasons.join(","), /profile_mismatch_rate/);
});

test("evaluateProviderRolloutGate passes healthy recent interpretation sample", () => {
  const summary = evaluateProviderRolloutGate(
    [
      {
        ts: "2026-04-03T00:00:00Z",
        requestId: "1",
        taskId: "ISSUE-1",
        module: "intake.interpretation",
        requestedProvider: "claude",
        effectiveProvider: "claude",
        outcome: "success",
        compareMode: "dry_run",
        primaryProvider: "local",
        shadowProvider: "claude",
        schemaValidShadow: true,
        profileMatch: true,
        targetFilesMatch: true,
        humanNeededMatch: true,
      },
      {
        ts: "2026-04-03T00:01:00Z",
        requestId: "2",
        taskId: "ISSUE-2",
        module: "intake.interpretation",
        requestedProvider: "claude",
        effectiveProvider: "claude",
        outcome: "success",
        compareMode: "dry_run",
        primaryProvider: "local",
        shadowProvider: "claude",
        schemaValidShadow: true,
        profileMatch: true,
        targetFilesMatch: true,
        humanNeededMatch: true,
      },
    ],
    { module: "intake.interpretation", minSamples: 2 },
  );

  assert.equal(summary.ready, true);
  assert.deepEqual(summary.blockingReasons, []);
});

test("evaluateProviderRolloutGate blocks when provider health reports auth error", () => {
  const summary = evaluateProviderRolloutGate(
    [
      {
        ts: "2026-04-03T00:00:00Z",
        requestId: "1",
        taskId: "ISSUE-1",
        module: "intake.interpretation",
        requestedProvider: "claude",
        effectiveProvider: "claude",
        outcome: "success",
        compareMode: "dry_run",
        primaryProvider: "local",
        shadowProvider: "claude",
        schemaValidShadow: true,
        profileMatch: true,
        targetFilesMatch: true,
        humanNeededMatch: true,
      },
    ],
    {
      module: "intake.interpretation",
      minSamples: 1,
      providerHealth: {
        status: "auth_error",
        lastErrorClass: "auth_forbidden",
      },
    },
  );

  assert.equal(summary.ready, false);
  assert.match(summary.blockingReasons.join(","), /provider_unhealthy:auth_forbidden/);
});
