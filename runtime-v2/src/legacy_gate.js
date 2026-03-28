"use strict";

const { evaluateAutomationGate } = require("./budget_policy");
const { evaluateExecutionStaleness } = require("./execution_policy");
const { syncLegacyShadowSnapshot } = require("./legacy_shadow");

function normalizeIssueNumber(issueNumber) {
  const parsed = Number.parseInt(String(issueNumber || ""), 10);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : null;
}

async function ensureShadowTask(store, taskId, issueNumber, repo) {
  const existingTask = await store.getTask(taskId);
  if (!existingTask) {
    await store.putTask({
      id: taskId,
      title: `Runtime v2 gate bootstrap ${taskId}`,
      repo,
      issueNumber: normalizeIssueNumber(issueNumber),
      meta: {
        runtimeV2Bootstrap: true,
      },
    });
  }

  const existingTaskState = await store.getTaskState(taskId);
  if (!existingTaskState) {
    await store.putTaskState({
      taskId,
      phase: "ready",
      reason: "runtime_v2_gate bootstrap",
      ownerMode: "human",
      meta: {
        source: "runtime_v2_gate_bootstrap",
      },
    });
  }
}

async function evaluateLegacyPolicyGate(store, input) {
  const {
    legacyStateDir,
    repo,
    taskId,
    issueNumber,
    rolloutMode,
    allowedTaskIds,
    expensive,
    sideEffectClass,
    maxExecutionsPerTask,
    maxTokenUsagePerTask,
    maxEstimatedCostPerTask,
    emergencyOnBreach,
    staleCheck,
    gateName,
  } = input;

  const sync = await syncLegacyShadowSnapshot(store, legacyStateDir, { repo });
  await ensureShadowTask(store, taskId, issueNumber, repo);

  const gate = await evaluateAutomationGate(store, taskId, {
    rolloutMode,
    allowedTaskIds,
    expensive,
    sideEffectClass,
    maxExecutionsPerTask,
    maxTokenUsagePerTask,
    maxEstimatedCostPerTask,
    emergencyOnBreach,
  });

  if (gate.status !== "applied") {
    return {
      status: "blocked",
      reason: gate.reason,
      gateName,
      gate,
      sync,
    };
  }

  const bundle = await store.getTaskBundle(taskId);
  if (staleCheck && bundle.activeExecution) {
    const stale = await evaluateExecutionStaleness(store, bundle.activeExecution.id);
    if (stale.status === "stale") {
      return {
        status: "blocked",
        reason: "stale_execution_detected",
        gateName,
        gate,
        stale,
        sync,
      };
    }
  }

  return {
    status: "applied",
    reason: "runtime_v2_gate_open",
    gateName,
    gate,
    sync,
    bundle,
  };
}

module.exports = {
  evaluateLegacyPolicyGate,
};
