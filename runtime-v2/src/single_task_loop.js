"use strict";

const { evaluateRolloutGate } = require("./budget_policy");
const { evaluateLegacyPolicyGate } = require("./legacy_gate");
const { applyLegacyEventBridge } = require("./legacy_event_bridge");
const { buildInspectionSummary } = require("./inspection");

async function runSingleTaskLoop(store, options = {}) {
  const legacyStateDir = options.legacyStateDir;
  const storeDir = options.storeDir;
  const repo = options.repo || "unknown/repo";
  const taskId = options.taskId || "PL-105-LOOP";
  const issueNumber = Number.isInteger(options.issueNumber) ? options.issueNumber : 105;
  const prNumber = Number.isInteger(options.prNumber) ? options.prNumber : 1050;
  const executionId = options.executionId || `${taskId}-exec-1`;

  const allowedGate = await evaluateLegacyPolicyGate(store, {
    legacyStateDir,
    repo,
    taskId,
    issueNumber,
    rolloutMode: "single_task",
    allowedTaskIds: [taskId],
    expensive: true,
    sideEffectClass: "expensive_ai",
    maxExecutionsPerTask: 3,
    maxTokenUsagePerTask: 60000,
    maxEstimatedCostPerTask: 25,
    emergencyOnBreach: true,
    staleCheck: false,
    gateName: "executor_start",
  });

  const deniedGate = evaluateRolloutGate({
    rolloutMode: "single_task",
    taskId: `${taskId}-DENIED`,
    allowedTaskIds: [taskId],
    expensive: true,
    sideEffectClass: "expensive_ai",
  });

  const events = [];
  events.push(
    await applyLegacyEventBridge(store, {
      legacyStateDir,
      repo,
      taskId,
      issueNumber,
      eventType: "execution.started",
      eventId: `${taskId}-exec-start`,
      dedupKey: `loop:${taskId}:execution.started:${executionId}`,
      source: "runtime_v2_single_task_loop",
      payload: {
        executionId,
      },
    }),
  );
  events.push(
    await applyLegacyEventBridge(store, {
      legacyStateDir,
      repo,
      taskId,
      issueNumber,
      eventType: "execution.finished",
      eventId: `${taskId}-exec-finish`,
      dedupKey: `loop:${taskId}:execution.finished:${executionId}`,
      source: "runtime_v2_single_task_loop",
      payload: {
        executionId,
      },
    }),
  );
  events.push(
    await applyLegacyEventBridge(store, {
      legacyStateDir,
      repo,
      taskId,
      issueNumber,
      eventType: "human.wait_requested",
      eventId: `${taskId}-wait`,
      dedupKey: `loop:${taskId}:human.wait_requested:comment-1`,
      source: "runtime_v2_single_task_loop",
      payload: {
        waitCommentId: `comment-${issueNumber}-wait-1`,
        reason: "need human answer before review handoff",
        kind: "QUESTION",
        commentUrl: `https://github.com/${repo}/issues/${issueNumber}#issuecomment-loop-wait`,
        pendingPost: false,
        waitingSince: "2026-03-28T21:00:00Z",
      },
    }),
  );
  events.push(
    await applyLegacyEventBridge(store, {
      legacyStateDir,
      repo,
      taskId,
      issueNumber,
      eventType: "human.response_received",
      eventId: `${taskId}-reply`,
      dedupKey: `loop:${taskId}:human.response_received:reply-1`,
      source: "runtime_v2_single_task_loop",
      payload: {
        responseType: "QUESTION",
        replyCommentId: `reply-${issueNumber}-1`,
      },
    }),
  );
  events.push(
    await applyLegacyEventBridge(store, {
      legacyStateDir,
      repo,
      taskId,
      issueNumber,
      eventType: "review.finalized",
      eventId: `${taskId}-review`,
      dedupKey: `loop:${taskId}:review.finalized:${prNumber}`,
      source: "runtime_v2_single_task_loop",
      payload: {
        prNumber,
        waitCommentId: `comment-${issueNumber}-review-1`,
        commentUrl: `https://github.com/${repo}/issues/${issueNumber}#issuecomment-loop-review`,
        pendingPost: true,
        waitingSince: "2026-03-28T21:10:00Z",
      },
    }),
  );

  const inspection = await buildInspectionSummary({
    store,
    legacyStateDir,
    storeDir,
    maxRecent: 10,
  });
  const primaryTask = inspection.tasks.recent.find((task) => task.taskId === taskId) || null;
  const reviewContext = inspection.contexts.review.find((item) => item.taskId === taskId) || null;

  const ok =
    allowedGate.status === "applied" &&
    deniedGate.status === "blocked" &&
    primaryTask &&
    primaryTask.phase === "reviewing" &&
    reviewContext &&
    reviewContext.prNumber === prNumber &&
    inspection.contexts.waitingCount === 0;

  return {
    generatedAt: new Date().toISOString(),
    repo,
    taskId,
    issueNumber,
    prNumber,
    allowedGate: {
      status: allowedGate.status,
      reason: allowedGate.reason,
    },
    deniedGate,
    events: events.map((item) => ({
      status: item.status,
      reason: item.reason,
      eventType: item.event.eventType,
    })),
    inspection: {
      controlMode: inspection.controlMode,
      tasks: inspection.tasks,
      contexts: inspection.contexts,
    },
    ok,
  };
}

module.exports = {
  runSingleTaskLoop,
};
