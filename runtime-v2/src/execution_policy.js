"use strict";

const crypto = require("crypto");

const { applyEvent } = require("./orchestrator");
const { ValidationError } = require("./errors");

function nowMs(options = {}) {
  if (options.now instanceof Date) {
    return options.now.getTime();
  }
  if (typeof options.now === "string") {
    const parsed = Date.parse(options.now);
    if (!Number.isNaN(parsed)) {
      return parsed;
    }
  }
  return Date.now();
}

function nowIso(options = {}) {
  return new Date(nowMs(options)).toISOString();
}

function buildExecutionDedupKey({ taskId, triggerEventId, executionType, phase, inputHash }) {
  const payload = JSON.stringify({
    taskId,
    triggerEventId,
    executionType,
    phase,
    inputHash,
  });
  return crypto.createHash("sha1").update(payload).digest("hex");
}

function assertPositiveInt(value, fieldName, fallback) {
  if (value === undefined || value === null) {
    return fallback;
  }
  if (!Number.isInteger(value) || value <= 0) {
    throw new ValidationError(`${fieldName} must be a positive integer`);
  }
  return value;
}

async function acquireExecutionLease(store, input, options = {}) {
  if (!input || typeof input !== "object") {
    throw new ValidationError("execution input is required");
  }
  const leaseDurationSec = assertPositiveInt(options.leaseDurationSec, "leaseDurationSec", 120);
  const startedAt = nowIso(options);
  const dedupKey =
    input.dedupKey ||
    buildExecutionDedupKey({
      taskId: input.taskId,
      triggerEventId: input.triggerEventId,
      executionType: input.executionType,
      phase: input.phase,
      inputHash: input.inputHash,
    });

  const existing = await store.findExecutionByDedupKey(input.taskId, dedupKey);
  if (existing) {
    return {
      status: "noop",
      reason: "duplicate_execution_dedup",
      dedupKey,
      existingExecutionId: existing.id,
    };
  }

  const transition = await applyEvent(store, {
    id: `event.execution.started.${input.id}`,
    taskId: input.taskId,
    eventType: "execution.started",
    source: "execution_policy",
    dedupKey: `execution.started:${input.id}`,
    payload: { executionId: input.id },
  });
  if (transition.status !== "applied") {
    return transition;
  }

  const execution = await store.putExecution({
    ...input,
    dedupKey,
    status: "running",
    startedAt,
    heartbeatAt: startedAt,
    leaseExpiresAt: new Date(nowMs(options) + leaseDurationSec * 1000).toISOString(),
  });

  return {
    status: "applied",
    reason: "execution_lease_acquired",
    dedupKey,
    execution,
  };
}

async function heartbeatExecutionLease(store, executionId, options = {}) {
  const leaseDurationSec = assertPositiveInt(options.leaseDurationSec, "leaseDurationSec", 120);
  const execution = await store.getExecution(executionId);
  if (!execution) {
    return {
      status: "noop",
      reason: "execution_not_found",
    };
  }
  if (execution.status !== "running") {
    return {
      status: "noop",
      reason: "execution_not_running",
      execution,
    };
  }

  const updated = await store.putExecution({
    ...execution,
    heartbeatAt: nowIso(options),
    leaseExpiresAt: new Date(nowMs(options) + leaseDurationSec * 1000).toISOString(),
  });

  return {
    status: "applied",
    reason: "execution_lease_heartbeat",
    execution: updated,
  };
}

async function releaseExecutionLease(store, executionId, options = {}) {
  const execution = await store.getExecution(executionId);
  if (!execution) {
    return {
      status: "noop",
      reason: "execution_not_found",
    };
  }

  const finalStatus = options.finalStatus || "succeeded";
  const updated = await store.putExecution({
    ...execution,
    status: finalStatus,
    finishedAt: nowIso(options),
    heartbeatAt: nowIso(options),
    leaseExpiresAt: null,
    terminationReason: options.terminationReason || execution.terminationReason || null,
    providerErrorClass: options.providerErrorClass || execution.providerErrorClass || null,
  });

  await applyEvent(store, {
    id: `event.execution.finished.${executionId}.${finalStatus}`,
    taskId: execution.taskId,
    eventType: "execution.finished",
    source: "execution_policy",
    dedupKey: `execution.finished:${executionId}:${finalStatus}`,
    payload: { executionId },
  });

  return {
    status: "applied",
    reason: "execution_lease_released",
    execution: updated,
  };
}

async function evaluateExecutionStaleness(store, executionId, options = {}) {
  const execution = await store.getExecution(executionId);
  if (!execution) {
    return {
      status: "noop",
      reason: "execution_not_found",
    };
  }
  if (execution.status !== "running") {
    return {
      status: "noop",
      reason: "execution_not_running",
      execution,
    };
  }
  if (!execution.leaseExpiresAt) {
    return {
      status: "stale",
      reason: "execution_has_no_lease",
      execution,
    };
  }
  const expired = Date.parse(execution.leaseExpiresAt) <= nowMs(options);
  return {
    status: expired ? "stale" : "healthy",
    reason: expired ? "execution_lease_expired" : "execution_lease_alive",
    execution,
  };
}

async function markExecutionStale(store, executionId, options = {}) {
  const stale = await evaluateExecutionStaleness(store, executionId, options);
  if (stale.status !== "stale") {
    return stale;
  }

  return releaseExecutionLease(store, executionId, {
    ...options,
    finalStatus: "failed",
    terminationReason: "stale_execution",
    providerErrorClass: "stale_execution",
  });
}

module.exports = {
  buildExecutionDedupKey,
  acquireExecutionLease,
  heartbeatExecutionLease,
  releaseExecutionLease,
  evaluateExecutionStaleness,
  markExecutionStale,
};
