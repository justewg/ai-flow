"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

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

module.exports = {
  collectLegacyShadowSnapshot,
  inferTaskStateFromLegacy,
  buildSnapshotHash,
};
