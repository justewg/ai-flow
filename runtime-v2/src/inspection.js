"use strict";

const fs = require("fs");
const path = require("path");

const { derivePrimaryContexts } = require("./primary_context");
const { deriveGlobalControlMode } = require("./control_policy");

function readJson(filePath, fallback) {
  if (!fs.existsSync(filePath)) {
    return fallback;
  }
  const raw = fs.readFileSync(filePath, "utf8").trim();
  if (!raw) {
    return fallback;
  }
  return JSON.parse(raw);
}

function readJsonLines(filePath) {
  if (!fs.existsSync(filePath)) {
    return [];
  }
  const raw = fs.readFileSync(filePath, "utf8").trim();
  if (!raw) {
    return [];
  }
  return raw
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line !== "")
    .map((line) => JSON.parse(line));
}

function readText(filePath) {
  if (!fs.existsSync(filePath)) {
    return "";
  }
  return fs.readFileSync(filePath, "utf8").trim();
}

function countBy(items, keySelector) {
  return items.reduce((acc, item) => {
    const key = String(keySelector(item) || "unknown");
    acc[key] = (acc[key] || 0) + 1;
    return acc;
  }, {});
}

function sortByTimestampDesc(items, selector) {
  return [...items].sort((left, right) => String(selector(right) || "").localeCompare(String(selector(left) || "")));
}

function summarizeExecutionSummary(summary) {
  const taskIds = Object.keys(summary).sort();
  const byLastRc = {};

  for (const taskId of taskIds) {
    const record = summary[taskId] || {};
    const key = String(record.lastRc || "unknown");
    byLastRc[key] = (byLastRc[key] || 0) + 1;
  }

  return {
    taskCount: taskIds.length,
    byLastRc,
    tasks: taskIds.map((taskId) => ({
      taskId,
      issueNumber: summary[taskId].issueNumber || "",
      count: Number(summary[taskId].count || 0),
      lastRc: summary[taskId].lastRc || "",
      lastFinishedAt: summary[taskId].lastFinishedAt || "",
      lastTerminationReason: summary[taskId].lastTerminationReason || "",
      lastProviderErrorClass: summary[taskId].lastProviderErrorClass || "",
    })),
  };
}

async function buildInspectionSummary({ store, legacyStateDir, storeDir, maxRecent = 10 }) {
  const [tasks, taskStates] = await Promise.all([store.listTasks(), store.listTaskStates()]);
  const taskById = new Map(tasks.map((task) => [task.id, task]));
  const primaryContexts = await derivePrimaryContexts(store);
  const derivedMode = deriveGlobalControlMode(taskStates);
  const recentTaskStates = sortByTimestampDesc(taskStates, (taskState) => taskState.updatedAt).slice(0, maxRecent);

  const incidentLedger = readJsonLines(path.join(legacyStateDir, "incident_ledger.jsonl"));
  const executionLedger = readJsonLines(path.join(legacyStateDir, "execution_ledger.jsonl"));
  const executionSummary = readJson(path.join(legacyStateDir, "execution_summary.json"), {});

  return {
    generatedAt: new Date().toISOString(),
    storeDir: path.resolve(storeDir),
    legacyStateDir: path.resolve(legacyStateDir),
    storePresent: fs.existsSync(path.resolve(storeDir)),
    controlMode: {
      current: readText(path.join(legacyStateDir, "flow_control_mode.txt")) || "AUTO",
      reason: readText(path.join(legacyStateDir, "flow_control_reason.txt")) || "",
      changedAt: readText(path.join(legacyStateDir, "flow_control_changed_at.txt")) || "",
      derived: derivedMode.mode,
      derivedReason: derivedMode.reason,
      derivedTaskId: derivedMode.taskId || null,
    },
    tasks: {
      total: taskStates.length,
      byPhase: countBy(taskStates, (taskState) => taskState.phase),
      byOwnerMode: countBy(taskStates, (taskState) => taskState.ownerMode),
      byBudgetState: countBy(taskStates, (taskState) => taskState.budgetState),
      byLockState: countBy(taskStates, (taskState) => taskState.lockState),
      activeExecutionCount: taskStates.filter((taskState) => taskState.activeExecutionId).length,
      canonicalReviewCount: taskStates.filter((taskState) => Number.isInteger(taskState.canonicalReviewPrNumber)).length,
      canonicalWaitCount: taskStates.filter((taskState) => taskState.canonicalWaitCommentId).length,
      recent: recentTaskStates.map((taskState) => ({
        taskId: taskState.taskId,
        issueNumber: (taskById.get(taskState.taskId) || {}).issueNumber || null,
        phase: taskState.phase,
        reason: taskState.reason,
        ownerMode: taskState.ownerMode,
        budgetState: taskState.budgetState,
        lockState: taskState.lockState,
        updatedAt: taskState.updatedAt,
      })),
    },
    contexts: {
      activeCount: primaryContexts.active.length,
      reviewCount: primaryContexts.review.length,
      waitingCount: primaryContexts.waiting.length,
      active: primaryContexts.active.slice(0, maxRecent),
      review: primaryContexts.review.slice(0, maxRecent),
      waiting: primaryContexts.waiting.slice(0, maxRecent),
    },
    incidents: {
      count: incidentLedger.length,
      recent: incidentLedger.slice(-maxRecent).reverse(),
    },
    executions: {
      ledgerCount: executionLedger.length,
      recent: executionLedger.slice(-maxRecent).reverse(),
      summary: summarizeExecutionSummary(executionSummary),
    },
  };
}

module.exports = {
  buildInspectionSummary,
};
