"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const { nowIso } = require("./schemas");

function readText(filePath) {
  try {
    const value = fs.readFileSync(filePath, "utf8").trim();
    return value || "";
  } catch (_error) {
    return "";
  }
}

function statePath(legacyStateDir, fileName) {
  return path.join(legacyStateDir, fileName);
}

function collectLegacyShadowSnapshot(legacyStateDir) {
  const snapshot = {
    controlMode: readText(statePath(legacyStateDir, "flow_control_mode.txt")) || "AUTO",
    controlReason: readText(statePath(legacyStateDir, "flow_control_reason.txt")),
    daemonActiveTask: readText(statePath(legacyStateDir, "daemon_active_task.txt")),
    daemonActiveIssueNumber: readText(statePath(legacyStateDir, "daemon_active_issue_number.txt")),
    daemonWaitingTaskId: readText(statePath(legacyStateDir, "daemon_waiting_task_id.txt")),
    daemonWaitingIssueNumber: readText(statePath(legacyStateDir, "daemon_waiting_issue_number.txt")),
    daemonWaitingCommentId: readText(statePath(legacyStateDir, "daemon_waiting_question_comment_id.txt")),
    daemonReviewTaskId: readText(statePath(legacyStateDir, "daemon_review_task_id.txt")),
    daemonReviewIssueNumber: readText(statePath(legacyStateDir, "daemon_review_issue_number.txt")),
    daemonReviewPrNumber: readText(statePath(legacyStateDir, "daemon_review_pr_number.txt")),
    executorTaskId: readText(statePath(legacyStateDir, "executor_task_id.txt")),
    executorIssueNumber: readText(statePath(legacyStateDir, "executor_issue_number.txt")),
    executorState: readText(statePath(legacyStateDir, "executor_state.txt")),
  };

  const taskIds = new Set(
    [
      snapshot.daemonActiveTask,
      snapshot.daemonWaitingTaskId,
      snapshot.daemonReviewTaskId,
      snapshot.executorTaskId,
    ].filter(Boolean),
  );

  return {
    snapshot,
    taskIds: Array.from(taskIds),
  };
}

function readJsonLines(filePath) {
  try {
    const raw = fs.readFileSync(filePath, "utf8");
    return raw
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter(Boolean)
      .map((line) => JSON.parse(line));
  } catch (_error) {
    return [];
  }
}

function collectLegacyExecutionRecords(legacyStateDir) {
  return readJsonLines(statePath(legacyStateDir, "execution_ledger.jsonl")).filter(
    (record) => record && typeof record.taskId === "string" && record.taskId.trim() !== "",
  );
}

function inferTaskStateFromLegacy(taskId, snapshot) {
  let phase = "planned";
  let reason = "legacy shadow sync";
  let activeExecutionId = null;
  let canonicalReviewPrNumber = null;
  let canonicalWaitCommentId = null;

  if (snapshot.daemonWaitingTaskId === taskId) {
    phase = "waiting_human";
    reason = "legacy daemon waiting";
    canonicalWaitCommentId = snapshot.daemonWaitingCommentId || null;
  } else if (snapshot.daemonReviewTaskId === taskId) {
    phase = "reviewing";
    reason = "legacy review handoff";
    canonicalReviewPrNumber = Number.parseInt(snapshot.daemonReviewPrNumber || "", 10);
    if (!Number.isInteger(canonicalReviewPrNumber) || canonicalReviewPrNumber < 1) {
      canonicalReviewPrNumber = null;
    }
  } else if (
    snapshot.executorTaskId === taskId &&
    ["RUNNING", "EXECUTOR_RUNNING"].includes((snapshot.executorState || "").toUpperCase())
  ) {
    phase = "executing";
    reason = "legacy executor running";
    activeExecutionId = `legacy-v2-exec-${taskId}`;
  } else if (snapshot.daemonActiveTask === taskId) {
    phase = "executing";
    reason = "legacy active task";
  }

  let budgetState = "normal";
  let lockState = "unlocked";
  if ((snapshot.controlMode || "AUTO") === "SAFE") {
    budgetState = "paused_budget";
    lockState = "frozen";
  } else if ((snapshot.controlMode || "AUTO") === "EMERGENCY_STOP") {
    budgetState = "emergency_stop";
    lockState = "frozen";
  }

  return {
    phase,
    reason,
    ownerMode: "human",
    activeExecutionId,
    canonicalReviewPrNumber,
    canonicalWaitCommentId,
    budgetState,
    lockState,
  };
}

function buildSnapshotHash(snapshotForTask) {
  return crypto.createHash("sha1").update(JSON.stringify(snapshotForTask)).digest("hex");
}

function buildLegacyExecutionRecordHash(record) {
  return crypto
    .createHash("sha1")
    .update(
      JSON.stringify({
        taskId: record.taskId || "",
        issueNumber: record.issueNumber || "",
        rc: record.rc || "",
        startedAt: record.startedAt || "",
        finishedAt: record.finishedAt || "",
        terminationReason: record.terminationReason || "",
        providerErrorClass: record.providerErrorClass || "",
        detached: Boolean(record.detached),
      }),
    )
    .digest("hex");
}

function projectLegacyExecutionRecord(record) {
  const recordHash = buildLegacyExecutionRecordHash(record);
  const status = String(record.rc || "") === "0" ? "succeeded" : "failed";
  const detached = Boolean(record.detached);
  return {
    id: `legacy-v2-record-${recordHash}`,
    taskId: String(record.taskId || "").trim(),
    triggerEventId: `legacy-v2-record-trigger-${recordHash}`,
    executionType: "implement",
    phase: "executing",
    dedupKey: `legacy_execution_record:${recordHash}`,
    status: detached ? "detached" : status,
    inputHash: `legacy_execution_record:${recordHash}`,
    sideEffectClass: "expensive_ai",
    startedAt: record.startedAt || nowIso(),
    finishedAt: record.finishedAt || nowIso(),
    tokenUsage: Number.isInteger(record.tokenUsage) ? record.tokenUsage : null,
    estimatedCost: typeof record.estimatedCost === "number" ? record.estimatedCost : null,
    terminationReason: record.terminationReason || null,
    providerErrorClass: record.providerErrorClass || null,
    meta: {
      source: "legacy_execution_record_v2",
      issueNumber: record.issueNumber || "",
      rc: record.rc || "",
      controlMode: record.controlMode || "",
      detached,
    },
  };
}

function strongestBudgetState(currentValue, nextValue) {
  const rank = {
    normal: 0,
    cooldown: 1,
    paused_budget: 2,
    emergency_stop: 3,
  };
  const currentRank = rank[currentValue] ?? 0;
  const nextRank = rank[nextValue] ?? 0;
  return currentRank >= nextRank ? currentValue : nextValue;
}

function strongestLockState(currentValue, nextValue) {
  const rank = {
    unlocked: 0,
    leased: 1,
    frozen: 2,
  };
  const currentRank = rank[currentValue] ?? 0;
  const nextRank = rank[nextValue] ?? 0;
  return currentRank >= nextRank ? currentValue : nextValue;
}

async function syncLegacyShadowSnapshot(store, legacyStateDir, options = {}) {
  const repo = options.repo || "unknown/repo";
  const { snapshot, taskIds: snapshotTaskIds } = collectLegacyShadowSnapshot(legacyStateDir);
  const executionRecords = collectLegacyExecutionRecords(legacyStateDir);
  const latestIssueByTask = new Map();

  for (const record of executionRecords) {
    if (record.issueNumber) {
      latestIssueByTask.set(record.taskId, record.issueNumber);
    }
  }

  const taskIds = new Set(snapshotTaskIds);
  for (const record of executionRecords) {
    taskIds.add(record.taskId);
  }

  const syncedTasks = [];
  for (const taskId of taskIds) {
    const taskStateProjection = inferTaskStateFromLegacy(taskId, snapshot);
    const existingTaskState = await store.getTaskState(taskId);
    const issueNumberRaw =
      snapshot.daemonWaitingTaskId === taskId
        ? snapshot.daemonWaitingIssueNumber
        : snapshot.daemonReviewTaskId === taskId
          ? snapshot.daemonReviewIssueNumber
          : snapshot.executorTaskId === taskId
            ? snapshot.executorIssueNumber
            : snapshot.daemonActiveTask === taskId
              ? snapshot.daemonActiveIssueNumber
              : latestIssueByTask.get(taskId) || "";
    const issueNumber = Number.parseInt(issueNumberRaw || "", 10);

    await store.putTask({
      id: taskId,
      title: `Legacy shadow task ${taskId}`,
      repo,
      issueNumber: Number.isInteger(issueNumber) && issueNumber > 0 ? issueNumber : null,
      meta: {
        legacyShadow: true,
      },
    });

    const nextTaskState = await store.putTaskState({
      taskId,
      ...taskStateProjection,
      ownerMode: existingTaskState && existingTaskState.ownerMode ? existingTaskState.ownerMode : taskStateProjection.ownerMode,
      attemptCount: existingTaskState && Number.isInteger(existingTaskState.attemptCount) ? existingTaskState.attemptCount : 0,
      budgetState: strongestBudgetState(existingTaskState && existingTaskState.budgetState, taskStateProjection.budgetState),
      lockState: strongestLockState(existingTaskState && existingTaskState.lockState, taskStateProjection.lockState),
      reason: `${taskStateProjection.reason}${snapshot.controlReason ? ` (${snapshot.controlReason})` : ""}`,
      meta: {
        source: "legacy_shadow_sync_v2",
      },
    });

    if (taskStateProjection.activeExecutionId) {
      await store.putExecution({
        id: taskStateProjection.activeExecutionId,
        taskId,
        triggerEventId: `legacy-shadow-trigger-${taskId}`,
        executionType: "reconcile",
        phase: "executing",
        dedupKey: `legacy-shadow-execution:${taskId}`,
        status: "running",
        inputHash: `legacy-shadow:${taskId}`,
        sideEffectClass: "state_only",
        meta: {
          source: "legacy_shadow_sync_v2",
        },
      });
    }

    const taskExecutionRecords = executionRecords.filter((record) => record.taskId === taskId);
    for (const record of taskExecutionRecords) {
      const projectedExecution = projectLegacyExecutionRecord(record);
      await store.putExecution(projectedExecution);
      const executionEventDedupKey = `legacy.execution_recorded:${projectedExecution.id}`;
      const existingEvent = await store.findEventByDedupKey(taskId, executionEventDedupKey);
      if (!existingEvent) {
        await store.appendEvent({
          id: `legacy-execution-event-${projectedExecution.id}`,
          taskId,
          eventType: "legacy.execution_recorded",
          source: "runtime_v2_shadow_sync",
          dedupKey: executionEventDedupKey,
          payload: {
            executionId: projectedExecution.id,
            status: projectedExecution.status,
            terminationReason: projectedExecution.terminationReason,
            providerErrorClass: projectedExecution.providerErrorClass,
          },
        });
      }
    }

    const snapshotHash = buildSnapshotHash({
      taskId,
      taskStateProjection: nextTaskState,
      issueNumber: Number.isInteger(issueNumber) && issueNumber > 0 ? issueNumber : null,
      controlMode: snapshot.controlMode,
    });
    const dedupKey = `legacy_shadow_snapshot:${taskId}:${snapshotHash}`;
    const existing = await store.findEventByDedupKey(taskId, dedupKey);
    if (!existing) {
      await store.appendEvent({
        id: `legacy-shadow-event-${taskId}-${snapshotHash}`,
        taskId,
        eventType: "legacy.shadow_synced",
        source: "runtime_v2_shadow_sync",
        dedupKey,
        payload: {
          controlMode: snapshot.controlMode,
          issueNumber: Number.isInteger(issueNumber) && issueNumber > 0 ? issueNumber : null,
          taskStateProjection: nextTaskState,
        },
      });
    }

    const bundle = await store.getTaskBundle(taskId);
    syncedTasks.push({
      taskId,
      phase: bundle.taskState ? bundle.taskState.phase : null,
      reviewPr: bundle.canonicalReviewPrNumber,
      waitingCommentId: bundle.canonicalWaitCommentId,
      activeExecutionId: bundle.activeExecution ? bundle.activeExecution.id : null,
      executionCount: (await store.listTaskExecutions(taskId)).length,
    });
  }

  return {
    snapshot,
    syncedTasks,
  };
}

module.exports = {
  collectLegacyShadowSnapshot,
  collectLegacyExecutionRecords,
  inferTaskStateFromLegacy,
  buildSnapshotHash,
  projectLegacyExecutionRecord,
  syncLegacyShadowSnapshot,
};
