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

function buildWaitingMeta(payload) {
  return {
    kind: payload.kind || null,
    waitCommentId: payload.waitCommentId || null,
    commentUrl: payload.commentUrl || null,
    pendingPost: payload.pendingPost === true,
    waitingSince: payload.waitingSince || null,
  };
}

function buildReviewFeedbackMeta(payload) {
  return {
    commentUrl: payload.commentUrl || null,
    pendingPost: payload.pendingPost === true,
    waitingSince: payload.waitingSince || null,
  };
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

  if (
    taskState.phase === "waiting_human" &&
    event.eventType !== "human.response_received" &&
    event.eventType !== "human.wait_requested" &&
    event.eventType !== "budget.breached"
  ) {
    return blocked("waiting_human_terminal", { event, taskState });
  }

  const nextState = {
    ...taskState,
    updatedAt: nowIso(),
    meta: {
      ...(taskState.meta || {}),
    },
  };

  switch (event.eventType) {
    case "task.claimed": {
      const itemId = event.payload.itemId;
      if (!itemId) {
        throw new ValidationError("task.claimed requires payload.itemId");
      }
      if (taskState.activeExecutionId) {
        return blocked("active_execution_exists", { event, taskState });
      }
      const meaning = transitionHash({
        eventType: event.eventType,
        itemId,
        issueNumber: event.payload.issueNumber || null,
        status: event.payload.status || null,
        flow: event.payload.flow || null,
      });
      if (taskState.phase === "claimed" && taskState.lastMeaningfulTransitionHash === meaning) {
        return noop("claim_already_applied", { event, taskState });
      }
      nextState.phase = "claimed";
      nextState.reason = event.payload.reason || "task claimed";
      nextState.activeExecutionId = null;
      nextState.meta.claim = {
        itemId,
        issueNumber: Number.isInteger(event.payload.issueNumber) ? event.payload.issueNumber : null,
        status: event.payload.status || null,
        flow: event.payload.flow || null,
        claimedAt: event.payload.claimedAt || nowIso(),
        source: event.payload.source || event.source || null,
      };
      nextState.lastMeaningfulTransitionHash = meaning;
      break;
    }

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
      nextState.meta.reviewFeedback = buildReviewFeedbackMeta(event.payload);
      nextState.lastMeaningfulTransitionHash = meaning;
      break;
    }

    case "review.feedback_wait_requested": {
      const waitCommentId = event.payload.waitCommentId;
      if (!waitCommentId) {
        throw new ValidationError("review.feedback_wait_requested requires payload.waitCommentId");
      }
      if (!taskState.canonicalReviewPrNumber) {
        return blocked("review_feedback_without_review", { event, taskState });
      }
      nextState.phase = "reviewing";
      nextState.reason = event.payload.reason || "awaiting review feedback";
      nextState.activeExecutionId = null;
      nextState.canonicalWaitCommentId = waitCommentId;
      nextState.meta.reviewFeedback = buildReviewFeedbackMeta(event.payload);
      nextState.lastMeaningfulTransitionHash = transitionHash({
        eventType: event.eventType,
        prNumber: taskState.canonicalReviewPrNumber,
        waitCommentId,
      });
      break;
    }

    case "review.terminal_resolved": {
      const outcome = event.payload.outcome || "resolved";
      nextState.phase = "done";
      nextState.reason = event.payload.reason || `review terminal resolved: ${outcome}`;
      nextState.activeExecutionId = null;
      nextState.canonicalWaitCommentId = null;
      nextState.budgetState = "normal";
      nextState.lockState = "unlocked";
      delete nextState.meta.waiting;
      delete nextState.meta.reviewFeedback;
      nextState.meta.reviewResolution = {
        outcome,
        prNumber: Number.isInteger(event.payload.prNumber) ? event.payload.prNumber : null,
        resolvedAt: event.payload.resolvedAt || nowIso(),
      };
      nextState.lastMeaningfulTransitionHash = transitionHash({
        eventType: event.eventType,
        outcome,
        prNumber: nextState.meta.reviewResolution.prNumber,
      });
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
      nextState.meta.waiting = buildWaitingMeta(event.payload);
      nextState.lastMeaningfulTransitionHash = transitionHash({
        eventType: event.eventType,
        waitCommentId,
      });
      break;
    }

    case "human.response_received": {
      nextState.phase = "ready";
      nextState.reason = event.payload.reason || "human response received";
      nextState.activeExecutionId = null;
      nextState.canonicalWaitCommentId = null;
      delete nextState.meta.waiting;
      delete nextState.meta.reviewFeedback;
      nextState.lastMeaningfulTransitionHash = transitionHash({
        eventType: event.eventType,
        responseType: event.payload.responseType || "generic",
      });
      break;
    }

    case "budget.breached": {
      const budgetState = event.payload.budgetState || "emergency_stop";
      nextState.phase = "paused";
      nextState.reason = event.payload.reason || "budget breach";
      nextState.activeExecutionId = null;
      nextState.budgetState = budgetState;
      nextState.lockState = "frozen";
      nextState.meta.budget = {
        breachReason: event.payload.breachReason || event.payload.reason || "budget_breach",
        providerErrorClass: event.payload.providerErrorClass || null,
        triggeredAt: event.payload.triggeredAt || nowIso(),
      };
      nextState.lastMeaningfulTransitionHash = transitionHash({
        eventType: event.eventType,
        budgetState,
        reason: nextState.reason,
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
