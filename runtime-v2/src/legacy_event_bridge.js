"use strict";

const crypto = require("crypto");

const { nowIso } = require("./schemas");
const { applyEvent } = require("./orchestrator");
const { syncLegacyShadowSnapshot } = require("./legacy_shadow");

function normalizeIssueNumber(issueNumber) {
  const parsed = Number.parseInt(String(issueNumber || ""), 10);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : null;
}

function autoEventId(taskId, eventType, dedupKey, payload) {
  const hash = crypto
    .createHash("sha1")
    .update(JSON.stringify({ taskId, eventType, dedupKey: dedupKey || "", payload: payload || {} }))
    .digest("hex");
  return `legacy-v2-event-${eventType}-${hash}`;
}

async function ensureTaskBootstrap(store, taskId, issueNumber, repo) {
  const existingTask = await store.getTask(taskId);
  if (!existingTask) {
    await store.putTask({
      id: taskId,
      title: `Runtime v2 event bridge bootstrap ${taskId}`,
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
      reason: "runtime_v2_event bootstrap",
      ownerMode: "human",
      updatedAt: nowIso(),
      meta: {
        source: "runtime_v2_event_bootstrap",
      },
    });
  }
}

async function applyLegacyEventBridge(store, input) {
  const {
    legacyStateDir,
    repo,
    taskId,
    issueNumber,
    eventType,
    eventId,
    source,
    dedupKey,
    payload,
  } = input;

  const sync = await syncLegacyShadowSnapshot(store, legacyStateDir, { repo });
  await ensureTaskBootstrap(store, taskId, issueNumber, repo);

  const event = {
    id: eventId || autoEventId(taskId, eventType, dedupKey, payload),
    taskId,
    eventType,
    source: source || "runtime_v2_event_bridge",
    dedupKey: dedupKey || null,
    payload: payload || {},
  };

  const result = await applyEvent(store, event);
  return {
    ...result,
    event,
    sync,
  };
}

module.exports = {
  applyLegacyEventBridge,
};
