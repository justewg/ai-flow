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

test("evaluateProviderRolloutGate does not block on tolerated target-file drift", () => {
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
        targetFilesMatch: false,
        targetFilesDriftKind: "shadow_subset",
        targetFilesDriftTolerated: true,
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
        targetFilesMatch: false,
        targetFilesDriftKind: "blocked_scope_drift",
        targetFilesDriftTolerated: true,
        humanNeededMatch: true,
      },
    ],
    { module: "intake.interpretation", minSamples: 2 },
  );

  assert.equal(summary.ready, true);
  assert.equal(summary.targetFilesMismatchCount, 2);
  assert.equal(summary.unsafeTargetFilesMismatchCount, 0);
  assert.deepEqual(summary.blockingReasons, []);
});

test("evaluateProviderRolloutGate does not block on conservative profile drift", () => {
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
        profileDriftKind: "conservative_shadow",
        profileDriftTolerated: true,
        targetFilesMatch: true,
        humanNeededMatch: true,
      },
    ],
    { module: "intake.interpretation", minSamples: 1 },
  );

  assert.equal(summary.ready, true);
  assert.equal(summary.profileMismatchCount, 1);
  assert.equal(summary.unsafeProfileMismatchCount, 0);
  assert.deepEqual(summary.blockingReasons, []);
});

test("evaluateProviderRolloutGate blocks on aggressive profile drift", () => {
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
        profileDriftKind: "aggressive_shadow",
        profileDriftTolerated: false,
        targetFilesMatch: true,
        humanNeededMatch: true,
      },
    ],
    { module: "intake.interpretation", minSamples: 1 },
  );

  assert.equal(summary.ready, false);
  assert.equal(summary.profileMismatchCount, 1);
  assert.equal(summary.unsafeProfileMismatchCount, 1);
  assert.match(summary.blockingReasons.join(","), /unsafe_profile_mismatch_rate/);
});

test("evaluateProviderRolloutGate blocks on unsafe target-file drift", () => {
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
        targetFilesMatch: false,
        targetFilesDriftKind: "different_files",
        targetFilesDriftTolerated: false,
        humanNeededMatch: true,
      },
    ],
    { module: "intake.interpretation", minSamples: 1 },
  );

  assert.equal(summary.ready, false);
  assert.equal(summary.unsafeTargetFilesMismatchCount, 1);
  assert.match(summary.blockingReasons.join(","), /unsafe_target_files_mismatch_rate/);
});

test("evaluateProviderRolloutGate checks ask-human kind and action drift", () => {
  const summary = evaluateProviderRolloutGate(
    [
      {
        ts: "2026-04-03T00:00:00Z",
        requestId: "1",
        taskId: "ISSUE-1",
        module: "intake.ask_human",
        requestedProvider: "claude",
        effectiveProvider: "claude",
        outcome: "success",
        compareMode: "dry_run",
        primaryProvider: "local",
        shadowProvider: "claude",
        schemaValidShadow: true,
        kindMatch: true,
        recommendedActionMatch: true,
        optionsMatch: false,
        machineReadableMarkersShadow: true,
        compareSummary: "ask_human_match",
      },
      {
        ts: "2026-04-03T00:01:00Z",
        requestId: "2",
        taskId: "ISSUE-2",
        module: "intake.ask_human",
        requestedProvider: "claude",
        effectiveProvider: "claude",
        outcome: "success",
        compareMode: "dry_run",
        primaryProvider: "local",
        shadowProvider: "claude",
        schemaValidShadow: true,
        kindMatch: false,
        recommendedActionMatch: true,
        optionsMatch: true,
        machineReadableMarkersShadow: true,
        compareSummary: "ask_human_kind_mismatch",
      },
    ],
    { module: "intake.ask_human", minSamples: 2 },
  );

  assert.equal(summary.ready, false);
  assert.equal(summary.askHumanKindMismatchCount, 1);
  assert.equal(summary.askHumanKindMismatchRate, 0.5);
  assert.equal(summary.askHumanActionMismatchCount, 0);
  assert.match(summary.blockingReasons.join(","), /ask_human_kind_mismatch_rate/);
  assert.equal(summary.lastRecords[0].kindMatch, true);
});

test("evaluateProviderRolloutGate blocks ask-human action drift", () => {
  const summary = evaluateProviderRolloutGate(
    [
      {
        ts: "2026-04-03T00:00:00Z",
        requestId: "1",
        taskId: "ISSUE-1",
        module: "intake.ask_human",
        requestedProvider: "claude",
        effectiveProvider: "claude",
        outcome: "success",
        compareMode: "dry_run",
        primaryProvider: "local",
        shadowProvider: "claude",
        schemaValidShadow: true,
        kindMatch: true,
        recommendedActionMatch: false,
        optionsMatch: true,
        machineReadableMarkersShadow: true,
        compareSummary: "ask_human_action_mismatch",
      },
    ],
    { module: "intake.ask_human", minSamples: 1 },
  );

  assert.equal(summary.ready, false);
  assert.equal(summary.askHumanActionMismatchCount, 1);
  assert.equal(summary.unsafeAskHumanActionMismatchCount, 1);
  assert.match(summary.blockingReasons.join(","), /unsafe_ask_human_action_mismatch_rate/);
});

test("evaluateProviderRolloutGate tolerates conservative ask-human action drift", () => {
  const summary = evaluateProviderRolloutGate(
    [
      {
        ts: "2026-04-03T00:00:00Z",
        requestId: "1",
        taskId: "ISSUE-1",
        module: "intake.ask_human",
        requestedProvider: "claude",
        effectiveProvider: "claude",
        outcome: "success",
        compareMode: "dry_run",
        primaryProvider: "local",
        shadowProvider: "claude",
        schemaValidShadow: true,
        kindMatch: true,
        recommendedActionMatch: false,
        recommendedActionDriftKind: "conservative_shadow",
        recommendedActionDriftTolerated: true,
        optionsMatch: false,
        machineReadableMarkersShadow: true,
        compareSummary: "ask_human_action_tolerated",
      },
    ],
    { module: "intake.ask_human", minSamples: 1 },
  );

  assert.equal(summary.ready, true);
  assert.equal(summary.askHumanActionMismatchCount, 1);
  assert.equal(summary.unsafeAskHumanActionMismatchCount, 0);
  assert.equal(summary.unsafeAskHumanActionMismatchRate, 0);
  assert.deepEqual(summary.blockingReasons, []);
  assert.equal(summary.lastRecords[0].recommendedActionDriftTolerated, true);
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
