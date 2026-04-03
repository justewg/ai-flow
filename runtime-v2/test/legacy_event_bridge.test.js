"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const os = require("os");
const path = require("path");

const {
  createAiFlowV2StateStore,
  createMemoryAdapter,
  applyLegacyEventBridge,
} = require("../src");

test("legacy event bridge moves task into waiting_human and back to ready", async () => {
  const stateDir = fs.mkdtempSync(path.join(os.tmpdir(), "aiflow-v2-event-wait-"));
  const store = createAiFlowV2StateStore({
    adapter: createMemoryAdapter(),
  });
  await store.init();

  const waitResult = await applyLegacyEventBridge(store, {
    legacyStateDir: stateDir,
    repo: "justewg/planka",
    taskId: "PL-097-WAIT",
    issueNumber: "700",
    eventType: "human.wait_requested",
    eventId: "evt-wait-1",
    dedupKey: "legacy.wait:PL-097-WAIT:comment-1",
    payload: {
      waitCommentId: "comment-1",
      reason: "need answer",
      kind: "BLOCKER",
      commentUrl: "https://github.com/justewg/planka/issues/700#issuecomment-1",
      pendingPost: false,
      waitingSince: "2026-03-28T20:00:00.000Z",
    },
  });
  assert.equal(waitResult.status, "applied");

  let bundle = await store.getTaskBundle("PL-097-WAIT");
  assert.equal(bundle.taskState.phase, "waiting_human");
  assert.equal(bundle.taskState.canonicalWaitCommentId, "comment-1");
  assert.deepEqual(bundle.taskState.meta.waiting, {
    kind: "BLOCKER",
    waitCommentId: "comment-1",
    commentUrl: "https://github.com/justewg/planka/issues/700#issuecomment-1",
    pendingPost: false,
    waitingSince: "2026-03-28T20:00:00.000Z",
  });

  const responseResult = await applyLegacyEventBridge(store, {
    legacyStateDir: stateDir,
    repo: "justewg/planka",
    taskId: "PL-097-WAIT",
    issueNumber: "700",
    eventType: "human.response_received",
    eventId: "evt-reply-1",
    dedupKey: "legacy.reply:PL-097-WAIT:reply-1",
    payload: {
      responseType: "BLOCKER",
      replyCommentId: "reply-1",
    },
  });
  assert.equal(responseResult.status, "applied");

  bundle = await store.getTaskBundle("PL-097-WAIT");
  assert.equal(bundle.taskState.phase, "ready");
  assert.equal(bundle.taskState.canonicalWaitCommentId, null);
  assert.equal(bundle.taskState.meta.waiting, undefined);
});

test("legacy event bridge persists canonical review artifact through review.finalized", async () => {
  const stateDir = fs.mkdtempSync(path.join(os.tmpdir(), "aiflow-v2-event-review-"));
  const store = createAiFlowV2StateStore({
    adapter: createMemoryAdapter(),
  });
  await store.init();

  const result = await applyLegacyEventBridge(store, {
    legacyStateDir: stateDir,
    repo: "justewg/planka",
    taskId: "PL-097-REVIEW",
    issueNumber: "701",
    eventType: "review.finalized",
    eventId: "evt-review-1",
    dedupKey: "legacy.review:PL-097-REVIEW:518",
    payload: {
      prNumber: 518,
      waitCommentId: "comment-518",
    },
  });

  assert.equal(result.status, "applied");
  const bundle = await store.getTaskBundle("PL-097-REVIEW");
  assert.equal(bundle.taskState.phase, "reviewing");
  assert.equal(bundle.canonicalReviewPrNumber, 518);
  assert.equal(bundle.canonicalWaitCommentId, "comment-518");
});

test("review.finalized can establish a fresh review anchor after human response cleared waiting anchor", async () => {
  const stateDir = fs.mkdtempSync(path.join(os.tmpdir(), "aiflow-v2-event-review-after-reply-"));
  const store = createAiFlowV2StateStore({
    adapter: createMemoryAdapter(),
  });
  await store.init();

  await applyLegacyEventBridge(store, {
    legacyStateDir: stateDir,
    repo: "justewg/planka",
    taskId: "PL-097-CHAIN",
    issueNumber: "703",
    eventType: "human.wait_requested",
    eventId: "evt-chain-wait",
    dedupKey: "legacy.wait:PL-097-CHAIN:comment-old",
    payload: {
      waitCommentId: "comment-old",
      reason: "need answer",
    },
  });

  await applyLegacyEventBridge(store, {
    legacyStateDir: stateDir,
    repo: "justewg/planka",
    taskId: "PL-097-CHAIN",
    issueNumber: "703",
    eventType: "human.response_received",
    eventId: "evt-chain-reply",
    dedupKey: "legacy.reply:PL-097-CHAIN:reply-1",
    payload: {
      responseType: "BLOCKER",
      replyCommentId: "reply-1",
    },
  });

  const reviewResult = await applyLegacyEventBridge(store, {
    legacyStateDir: stateDir,
    repo: "justewg/planka",
    taskId: "PL-097-CHAIN",
    issueNumber: "703",
    eventType: "review.finalized",
    eventId: "evt-chain-review",
    dedupKey: "legacy.review:PL-097-CHAIN:520",
    payload: {
      prNumber: 520,
      waitCommentId: "comment-review-520",
    },
  });

  assert.equal(reviewResult.status, "applied");
  const bundle = await store.getTaskBundle("PL-097-CHAIN");
  assert.equal(bundle.taskState.phase, "reviewing");
  assert.equal(bundle.canonicalReviewPrNumber, 520);
  assert.equal(bundle.canonicalWaitCommentId, "comment-review-520");
});

test("legacy event bridge updates execution lifecycle through applyEvent", async () => {
  const stateDir = fs.mkdtempSync(path.join(os.tmpdir(), "aiflow-v2-event-exec-"));
  const store = createAiFlowV2StateStore({
    adapter: createMemoryAdapter(),
  });
  await store.init();

  const started = await applyLegacyEventBridge(store, {
    legacyStateDir: stateDir,
    repo: "justewg/planka",
    taskId: "PL-097-EXEC",
    issueNumber: "702",
    eventType: "execution.started",
    eventId: "evt-exec-start-1",
    dedupKey: "legacy.exec.start:PL-097-EXEC:exec-1",
    payload: {
      executionId: "exec-1",
    },
  });
  assert.equal(started.status, "applied");

  let bundle = await store.getTaskBundle("PL-097-EXEC");
  assert.equal(bundle.taskState.phase, "executing");
  assert.equal(bundle.taskState.activeExecutionId, "exec-1");

  const finished = await applyLegacyEventBridge(store, {
    legacyStateDir: stateDir,
    repo: "justewg/planka",
    taskId: "PL-097-EXEC",
    issueNumber: "702",
    eventType: "execution.finished",
    eventId: "evt-exec-finish-1",
    dedupKey: "legacy.exec.finish:PL-097-EXEC:exec-1",
    payload: {
      executionId: "exec-1",
    },
  });
  assert.equal(finished.status, "applied");

  bundle = await store.getTaskBundle("PL-097-EXEC");
  assert.equal(bundle.taskState.phase, "ready");
  assert.equal(bundle.taskState.activeExecutionId, null);
});

test("legacy event bridge persists claim bootstrap before execution starts", async () => {
  const stateDir = fs.mkdtempSync(path.join(os.tmpdir(), "aiflow-v2-event-claim-"));
  const store = createAiFlowV2StateStore({
    adapter: createMemoryAdapter(),
  });
  await store.init();

  const claimed = await applyLegacyEventBridge(store, {
    legacyStateDir: stateDir,
    repo: "justewg/planka",
    taskId: "PL-097-CLAIM",
    issueNumber: "705",
    eventType: "task.claimed",
    eventId: "evt-claim-1",
    dedupKey: "legacy.claim:PL-097-CLAIM:PVTI_705",
    payload: {
      itemId: "PVTI_705",
      issueNumber: 705,
      status: "In Progress",
      flow: "In Progress",
      claimedAt: "2026-03-28T20:05:00.000Z",
    },
  });
  assert.equal(claimed.status, "applied");

  let bundle = await store.getTaskBundle("PL-097-CLAIM");
  assert.equal(bundle.taskState.phase, "claimed");
  assert.equal(bundle.taskState.activeExecutionId, null);
  assert.deepEqual(bundle.taskState.meta.claim, {
    itemId: "PVTI_705",
    issueNumber: 705,
    status: "In Progress",
    flow: "In Progress",
    claimedAt: "2026-03-28T20:05:00.000Z",
    source: "runtime_v2_event_bridge",
  });

  const started = await applyLegacyEventBridge(store, {
    legacyStateDir: stateDir,
    repo: "justewg/planka",
    taskId: "PL-097-CLAIM",
    issueNumber: "705",
    eventType: "execution.started",
    eventId: "evt-claim-exec-1",
    dedupKey: "legacy.exec.start:PL-097-CLAIM:exec-1",
    payload: {
      executionId: "exec-1",
    },
  });
  assert.equal(started.status, "applied");

  bundle = await store.getTaskBundle("PL-097-CLAIM");
  assert.equal(bundle.taskState.phase, "executing");
  assert.equal(bundle.taskState.activeExecutionId, "exec-1");
  assert.equal(bundle.taskState.meta.claim.itemId, "PVTI_705");
});

test("review feedback wait request updates review anchor without leaving reviewing phase", async () => {
  const stateDir = fs.mkdtempSync(path.join(os.tmpdir(), "aiflow-v2-event-review-feedback-"));
  const store = createAiFlowV2StateStore({
    adapter: createMemoryAdapter(),
  });
  await store.init();

  await applyLegacyEventBridge(store, {
    legacyStateDir: stateDir,
    repo: "justewg/planka",
    taskId: "PL-100-REVIEW",
    issueNumber: "704",
    eventType: "review.finalized",
    eventId: "evt-review-feedback-bootstrap",
    dedupKey: "legacy.review:PL-100-REVIEW:521",
    payload: {
      prNumber: 521,
      waitCommentId: "comment-review-1",
      commentUrl: "https://github.com/justewg/planka/issues/704#issuecomment-1",
      pendingPost: false,
      waitingSince: "2026-03-28T20:10:00.000Z",
    },
  });

  const result = await applyLegacyEventBridge(store, {
    legacyStateDir: stateDir,
    repo: "justewg/planka",
    taskId: "PL-100-REVIEW",
    issueNumber: "704",
    eventType: "review.feedback_wait_requested",
    eventId: "evt-review-feedback-wait",
    dedupKey: "legacy.review.feedback_wait_requested:PL-100-REVIEW:comment-review-2",
    payload: {
      waitCommentId: "comment-review-2",
      commentUrl: "https://github.com/justewg/planka/issues/704#issuecomment-2",
      pendingPost: true,
      waitingSince: "2026-03-28T20:11:00.000Z",
      reason: "awaiting review feedback clarification",
    },
  });

  assert.equal(result.status, "applied");
  const bundle = await store.getTaskBundle("PL-100-REVIEW");
  assert.equal(bundle.taskState.phase, "reviewing");
  assert.equal(bundle.taskState.canonicalReviewPrNumber, 521);
  assert.equal(bundle.taskState.canonicalWaitCommentId, "comment-review-2");
  assert.deepEqual(bundle.taskState.meta.reviewFeedback, {
    commentUrl: "https://github.com/justewg/planka/issues/704#issuecomment-2",
    pendingPost: true,
    waitingSince: "2026-03-28T20:11:00.000Z",
  });
});
