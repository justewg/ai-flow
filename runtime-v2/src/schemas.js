"use strict";

const { ValidationError } = require("./errors");

const TASK_STATE_PHASES = new Set([
  "new",
  "planned",
  "ready",
  "claimed",
  "executing",
  "waiting_human",
  "reviewing",
  "done",
  "blocked",
  "paused",
]);

const OWNER_MODES = new Set(["auto", "human", "mixed", "blocked"]);
const EXECUTION_STATUSES = new Set(["running", "succeeded", "failed", "cancelled", "detached"]);
const EXECUTION_TYPES = new Set(["plan", "implement", "finalize", "reconcile", "supervisor"]);
const SIDE_EFFECT_CLASSES = new Set(["read_only", "state_only", "github_comment", "pr", "expensive_ai"]);
const BUDGET_STATES = new Set(["normal", "cooldown", "paused_budget", "emergency_stop"]);
const LOCK_STATES = new Set(["unlocked", "leased", "frozen"]);

function nowIso() {
  return new Date().toISOString();
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function assertString(value, fieldName) {
  if (typeof value !== "string" || value.trim() === "") {
    throw new ValidationError(`${fieldName} must be a non-empty string`, { fieldName });
  }
  return value.trim();
}

function optionalString(value) {
  if (value === undefined || value === null || value === "") {
    return null;
  }
  if (typeof value !== "string") {
    throw new ValidationError("optional string field must be a string");
  }
  return value;
}

function optionalNumber(value, fieldName) {
  if (value === undefined || value === null || value === "") {
    return null;
  }
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new ValidationError(`${fieldName} must be a finite number`, { fieldName });
  }
  return value;
}

function optionalInteger(value, fieldName) {
  if (value === undefined || value === null || value === "") {
    return null;
  }
  if (!Number.isInteger(value) || value < 0) {
    throw new ValidationError(`${fieldName} must be a non-negative integer`, { fieldName });
  }
  return value;
}

function optionalIsoDate(value, fieldName) {
  if (value === undefined || value === null || value === "") {
    return null;
  }
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    throw new ValidationError(`${fieldName} must be a valid ISO date`, { fieldName });
  }
  return date.toISOString();
}

function optionalObject(value, fieldName) {
  if (value === undefined || value === null) {
    return {};
  }
  if (!isPlainObject(value)) {
    throw new ValidationError(`${fieldName} must be an object`, { fieldName });
  }
  return value;
}

function assertEnum(value, allowedSet, fieldName) {
  const normalized = assertString(value, fieldName);
  if (!allowedSet.has(normalized)) {
    throw new ValidationError(`${fieldName} has unsupported value: ${normalized}`, { fieldName, value: normalized });
  }
  return normalized;
}

function normalizeTask(input) {
  if (!isPlainObject(input)) {
    throw new ValidationError("task must be an object");
  }
  const createdAt = optionalIsoDate(input.createdAt, "createdAt") || nowIso();
  const updatedAt = optionalIsoDate(input.updatedAt, "updatedAt") || createdAt;

  return {
    kind: "task",
    id: assertString(input.id, "id"),
    title: assertString(input.title, "title"),
    repo: assertString(input.repo, "repo"),
    issueNumber: optionalInteger(input.issueNumber, "issueNumber"),
    createdAt,
    updatedAt,
    meta: optionalObject(input.meta, "meta"),
  };
}

function normalizeTaskState(input) {
  if (!isPlainObject(input)) {
    throw new ValidationError("task state must be an object");
  }
  return {
    kind: "task_state",
    taskId: assertString(input.taskId, "taskId"),
    phase: assertEnum(input.phase, TASK_STATE_PHASES, "phase"),
    reason: assertString(input.reason, "reason"),
    ownerMode: assertEnum(input.ownerMode, OWNER_MODES, "ownerMode"),
    activeExecutionId: optionalString(input.activeExecutionId),
    canonicalReviewPrNumber: optionalInteger(input.canonicalReviewPrNumber, "canonicalReviewPrNumber"),
    canonicalWaitCommentId: optionalString(input.canonicalWaitCommentId),
    attemptCount: optionalInteger(input.attemptCount, "attemptCount") ?? 0,
    cooldownUntil: optionalIsoDate(input.cooldownUntil, "cooldownUntil"),
    budgetState: assertEnum(input.budgetState || "normal", BUDGET_STATES, "budgetState"),
    lockState: assertEnum(input.lockState || "unlocked", LOCK_STATES, "lockState"),
    lastMeaningfulTransitionHash: optionalString(input.lastMeaningfulTransitionHash),
    updatedAt: optionalIsoDate(input.updatedAt, "updatedAt") || nowIso(),
    meta: optionalObject(input.meta, "meta"),
  };
}

function normalizeExecution(input) {
  if (!isPlainObject(input)) {
    throw new ValidationError("execution must be an object");
  }
  const startedAt = optionalIsoDate(input.startedAt, "startedAt") || nowIso();
  return {
    kind: "execution",
    id: assertString(input.id, "id"),
    taskId: assertString(input.taskId, "taskId"),
    triggerEventId: assertString(input.triggerEventId, "triggerEventId"),
    executionType: assertEnum(input.executionType, EXECUTION_TYPES, "executionType"),
    phase: assertString(input.phase, "phase"),
    dedupKey: assertString(input.dedupKey, "dedupKey"),
    status: assertEnum(input.status, EXECUTION_STATUSES, "status"),
    inputHash: assertString(input.inputHash, "inputHash"),
    sideEffectClass: assertEnum(input.sideEffectClass, SIDE_EFFECT_CLASSES, "sideEffectClass"),
    startedAt,
    finishedAt: optionalIsoDate(input.finishedAt, "finishedAt"),
    leaseExpiresAt: optionalIsoDate(input.leaseExpiresAt, "leaseExpiresAt"),
    heartbeatAt: optionalIsoDate(input.heartbeatAt, "heartbeatAt"),
    tokenUsage: optionalInteger(input.tokenUsage, "tokenUsage"),
    estimatedCost: optionalNumber(input.estimatedCost, "estimatedCost"),
    terminationReason: optionalString(input.terminationReason),
    providerErrorClass: optionalString(input.providerErrorClass),
    meta: optionalObject(input.meta, "meta"),
  };
}

function normalizeEvent(input) {
  if (!isPlainObject(input)) {
    throw new ValidationError("event must be an object");
  }
  return {
    kind: "event",
    id: assertString(input.id, "id"),
    taskId: assertString(input.taskId, "taskId"),
    eventType: assertString(input.eventType, "eventType"),
    source: assertString(input.source, "source"),
    dedupKey: optionalString(input.dedupKey),
    createdAt: optionalIsoDate(input.createdAt, "createdAt") || nowIso(),
    payload: optionalObject(input.payload, "payload"),
  };
}

module.exports = {
  TASK_STATE_PHASES,
  OWNER_MODES,
  EXECUTION_STATUSES,
  EXECUTION_TYPES,
  SIDE_EFFECT_CLASSES,
  BUDGET_STATES,
  LOCK_STATES,
  nowIso,
  normalizeTask,
  normalizeTaskState,
  normalizeExecution,
  normalizeEvent,
};
