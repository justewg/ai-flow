"use strict";

const crypto = require("crypto");

const { nowIso } = require("./schemas");
const { ValidationError } = require("./errors");

function transitionHash(payload) {
  return crypto.createHash("sha1").update(JSON.stringify(payload)).digest("hex");
}

function assertStore(store) {
  if (!store || typeof store.getTaskBundle !== "function") {
    throw new ValidationError("orchestrator requires a valid store");
  }
}

function noop(reason, extra = {}) {
  return {
    status: "noop",
    reason,
    ...extra,
  };
}

function applied(reason, extra = {}) {
  return {
    status: "applied",
    reason,
    ...extra,
  };
}

function blocked(reason, extra = {}) {
  return {
    status: "blocked",
    reason,
    ...extra,
  };
}

function ensureEventShape(event) {
  if (!event || typeof event !== "object") {
    throw new ValidationError("event is required");
  }
  if (!event.id || !event.taskId || !event.eventType || !event.source) {
    throw new ValidationError("event must have id, taskId, eventType and source");
  }
}

async function applyEvent(store, eventInput) {
  assertStore(store);
  ensureEventShape(eventInput);

  const event = {
    payload: {},
    createdAt: nowIso(),
    ...eventInput,
  };

  if (event.dedupKey) {
    const existing = await store.findEventByDedupKey(event.taskId, event.dedupKey);
    if (existing) {
      return noop("duplicate_event", { event, existingEventId: existing.id });
    }
  }

  const bundle = await store.getTaskBundle(event.taskId);
  const taskState =
    bundle.taskState ||
    {
      taskId: event.taskId,
      phase: "new",
      reason: "implicit bootstrap",
      ownerMode: "human",
      activeExecutionId: null,
      canonicalReviewPrNumber: null,
      canonicalWaitCommentId: null,
      attemptCount: 0,
      cooldownUntil: null,
      budgetState: "normal",
      lockState: "unlocked",
      lastMeaningfulTransitionHash: null,
      updatedAt: nowIso(),
      meta: {},
    };

  if (taskState.phase === "waiting_human" && event.eventType !== "human.response_received" && event.eventType !== "human.wait_requested") {
    return blocked("waiting_human_terminal", { event, taskState });
  }

  const nextState = {
    ...taskState,
    updatedAt: nowIso(),
  };

  switch (event.eventType) {
    case "execution.started": {
      const executionId = event.payload.executionId;
      if (!executionId) {
        throw new ValidationError("execution.started requires payload.executionId");
      }
      if (taskState.activeExecutionId && taskState.activeExecutionId !== executionId) {
        return blocked("active_execution_exists", { event, taskState });
      }
      nextState.phase = "executing";
      nextState.reason = "execution started";
      nextState.activeExecutionId = executionId;
      nextState.lastMeaningfulTransitionHash = transitionHash({
        eventType: event.eventType,
        executionId,
      });
      break;
    }

    case "execution.finished": {
      const executionId = event.payload.executionId;
      if (taskState.activeExecutionId && executionId && taskState.activeExecutionId !== executionId) {
        return blocked("execution_mismatch", { event, taskState });
      }
      nextState.phase = "ready";
      nextState.reason = "execution finished";
      nextState.activeExecutionId = null;
      nextState.lastMeaningfulTransitionHash = transitionHash({
        eventType: event.eventType,
        executionId: executionId || null,
      });
      break;
    }

    case "review.finalized": {
      const prNumber = event.payload.prNumber;
      const waitCommentId = event.payload.waitCommentId || null;
      if (!Number.isInteger(prNumber) || prNumber < 1) {
        throw new ValidationError("review.finalized requires integer payload.prNumber");
      }
      if (taskState.canonicalReviewPrNumber && taskState.canonicalReviewPrNumber !== prNumber) {
        return noop("canonical_review_pr_exists", {
          event,
          taskState,
          canonicalReviewPrNumber: taskState.canonicalReviewPrNumber,
        });
      }
      if (
        taskState.canonicalWaitCommentId &&
        waitCommentId &&
        taskState.canonicalWaitCommentId !== waitCommentId
      ) {
        return noop("canonical_review_comment_exists", {
          event,
          taskState,
          canonicalWaitCommentId: taskState.canonicalWaitCommentId,
        });
      }

      const meaning = transitionHash({
        eventType: event.eventType,
        prNumber,
        waitCommentId,
      });
      if (taskState.lastMeaningfulTransitionHash === meaning) {
        return noop("finalize_without_new_event", { event, taskState });
      }

      nextState.phase = "reviewing";
      nextState.reason = "awaiting review";
      nextState.activeExecutionId = null;
      nextState.canonicalReviewPrNumber = prNumber;
      nextState.canonicalWaitCommentId = waitCommentId || taskState.canonicalWaitCommentId;
      nextState.lastMeaningfulTransitionHash = meaning;
      break;
    }

    case "human.wait_requested": {
      const waitCommentId = event.payload.waitCommentId;
      if (!waitCommentId) {
        throw new ValidationError("human.wait_requested requires payload.waitCommentId");
      }
      if (taskState.canonicalWaitCommentId && taskState.canonicalWaitCommentId !== waitCommentId) {
        return noop("canonical_wait_comment_exists", {
          event,
          taskState,
          canonicalWaitCommentId: taskState.canonicalWaitCommentId,
        });
      }
      nextState.phase = "waiting_human";
      nextState.reason = event.payload.reason || "waiting human reply";
      nextState.activeExecutionId = null;
      nextState.canonicalWaitCommentId = waitCommentId;
      nextState.lastMeaningfulTransitionHash = transitionHash({
        eventType: event.eventType,
        waitCommentId,
      });
      break;
    }

    case "human.response_received": {
      nextState.phase = "ready";
      nextState.reason = event.payload.reason || "human response received";
      nextState.lastMeaningfulTransitionHash = transitionHash({
        eventType: event.eventType,
        responseType: event.payload.responseType || "generic",
      });
      break;
    }

    default:
      return noop("unhandled_event_type", { event, taskState });
  }

  await store.appendEvent(event);
  await store.putTaskState(nextState);
  return applied("state_transition_applied", {
    event,
    taskState: nextState,
  });
}

module.exports = {
  applyEvent,
};
