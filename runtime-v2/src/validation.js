"use strict";

const { evaluateRolloutGate } = require("./budget_policy");
const { evaluateLegacyPolicyGate } = require("./legacy_gate");
const { applyLegacyEventBridge } = require("./legacy_event_bridge");
const { buildInspectionSummary } = require("./inspection");

async function runRolloutValidation(store, options = {}) {
  const legacyStateDir = options.legacyStateDir;
  const storeDir = options.storeDir;
  const repo = options.repo || "unknown/repo";
  const taskId = options.taskId || "PL-104-VALIDATION";
  const issueNumber = Number.isInteger(options.issueNumber) ? options.issueNumber : 104;
  const maxExecutionsPerTask = Number.isInteger(options.maxExecutionsPerTask) ? options.maxExecutionsPerTask : 3;
  const maxTokenUsagePerTask = Number.isInteger(options.maxTokenUsagePerTask) ? options.maxTokenUsagePerTask : 60000;
  const maxEstimatedCostPerTask =
    typeof options.maxEstimatedCostPerTask === "number" ? options.maxEstimatedCostPerTask : 25;

  async function gateScenario(name, rolloutMode, gateName, sideEffectClass, expensive) {
    const result = await evaluateLegacyPolicyGate(store, {
      legacyStateDir,
      repo,
      taskId,
      issueNumber,
      rolloutMode,
      allowedTaskIds: [],
      expensive,
      sideEffectClass,
      maxExecutionsPerTask,
      maxTokenUsagePerTask,
      maxEstimatedCostPerTask,
      emergencyOnBreach: true,
      staleCheck: false,
      gateName,
    });
    return {
      name,
      rolloutMode,
      gateName,
      sideEffectClass,
      expensive,
      status: result.status,
      reason: result.reason,
    };
  }

  const scenarios = [];
  scenarios.push(await gateScenario("dry_run_daemon_claim", "dry_run", "daemon_claim", "state_only", true));
  scenarios.push(await gateScenario("dry_run_executor_start", "dry_run", "executor_start", "expensive_ai", true));
  scenarios.push(await gateScenario("shadow_daemon_claim", "shadow", "daemon_claim", "state_only", true));
  scenarios.push(await gateScenario("shadow_executor_start", "shadow", "executor_start", "expensive_ai", true));
  scenarios.push({
    name: "shadow_read_only_inspection",
    rolloutMode: "shadow",
    gateName: "inspection",
    sideEffectClass: "read_only",
    expensive: false,
    ...evaluateRolloutGate({
      rolloutMode: "shadow",
      taskId,
      allowedTaskIds: [],
      sideEffectClass: "read_only",
      expensive: false,
    }),
  });

  const waitEvent = await applyLegacyEventBridge(store, {
    legacyStateDir,
    repo,
    taskId,
    issueNumber,
    eventType: "human.wait_requested",
    eventId: `validation-${taskId}-wait`,
    source: "runtime_v2_validation",
    dedupKey: `validation:${taskId}:wait`,
    payload: {
      reason: "validation wait anchor",
      waitCommentId: `validation-comment-${issueNumber}`,
      kind: "QUESTION",
      commentUrl: `https://github.com/${repo}/issues/${issueNumber}#issuecomment-validation`,
      pendingPost: false,
      waitingSince: "2026-03-28T20:00:00Z",
    },
  });

  const inspection = await buildInspectionSummary({
    store,
    legacyStateDir,
    storeDir,
    maxRecent: 10,
  });

  const expectations = [
    { name: "dry_run_daemon_claim", status: "blocked", reason: "rollout_dry_run" },
    { name: "dry_run_executor_start", status: "blocked", reason: "rollout_dry_run" },
    { name: "shadow_daemon_claim", status: "blocked", reason: "rollout_shadow_blocks_side_effects" },
    { name: "shadow_executor_start", status: "blocked", reason: "rollout_shadow_blocks_side_effects" },
    { name: "shadow_read_only_inspection", status: "applied", reason: "rollout_shadow_read_only" },
  ];

  const failedExpectations = expectations.filter((expected) => {
    const actual = scenarios.find((scenario) => scenario.name === expected.name);
    return !actual || actual.status !== expected.status || actual.reason !== expected.reason;
  });

  const waitExpectationMet =
    (waitEvent.status === "applied" || (waitEvent.status === "noop" && waitEvent.reason === "duplicate_event")) &&
    inspection.contexts.waitingCount === 1 &&
    inspection.contexts.waiting[0] &&
    inspection.contexts.waiting[0].taskId === taskId;

  return {
    generatedAt: new Date().toISOString(),
    repo,
    taskId,
    issueNumber,
    scenarios,
    waitEvent: {
      status: waitEvent.status,
      reason: waitEvent.reason,
      eventType: waitEvent.event.eventType,
    },
    inspection: {
      controlMode: inspection.controlMode,
      tasks: inspection.tasks,
      contexts: inspection.contexts,
    },
    ok: failedExpectations.length === 0 && waitExpectationMet,
    failures: {
      expectations: failedExpectations,
      waitExpectationMet,
    },
  };
}

module.exports = {
  runRolloutValidation,
};
