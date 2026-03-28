"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  createAiFlowV2StateStore,
  createMemoryAdapter,
  derivePrimaryContexts,
} = require("../src");

test("primary contexts derive active and review slices from task states", async () => {
  const store = createAiFlowV2StateStore({
    adapter: createMemoryAdapter(),
  });
  await store.init();

  await store.putTask({ id: "PL-098-ACTIVE", title: "active", repo: "justewg/planka", issueNumber: 801 });
  await store.putTask({ id: "PL-098-REVIEW", title: "review", repo: "justewg/planka", issueNumber: 802 });
  await store.putTask({ id: "PL-099-WAIT", title: "wait", repo: "justewg/planka", issueNumber: 803 });
  await store.putTaskState({
    taskId: "PL-098-ACTIVE",
    phase: "executing",
    reason: "running",
    ownerMode: "human",
    activeExecutionId: "exec-801",
    updatedAt: "2026-03-28T19:30:00.000Z",
  });
  await store.putTaskState({
    taskId: "PL-098-REVIEW",
    phase: "reviewing",
    reason: "awaiting review",
    ownerMode: "human",
    canonicalReviewPrNumber: 700,
    updatedAt: "2026-03-28T19:31:00.000Z",
  });
  await store.putTaskState({
    taskId: "PL-099-WAIT",
    phase: "waiting_human",
    reason: "waiting answer",
    ownerMode: "human",
    canonicalWaitCommentId: "comment-803",
    updatedAt: "2026-03-28T19:32:00.000Z",
    meta: {
      waiting: {
        kind: "BLOCKER",
        waitCommentId: "comment-803",
        commentUrl: "https://github.com/justewg/planka/issues/803#issuecomment-1",
        pendingPost: false,
        waitingSince: "2026-03-28T19:32:00.000Z",
      },
    },
  });

  const contexts = await derivePrimaryContexts(store);
  assert.equal(contexts.active.length, 1);
  assert.equal(contexts.active[0].taskId, "PL-098-ACTIVE");
  assert.equal(contexts.active[0].issueNumber, 801);
  assert.equal(contexts.review.length, 1);
  assert.equal(contexts.review[0].taskId, "PL-098-REVIEW");
  assert.equal(contexts.review[0].issueNumber, 802);
  assert.equal(contexts.review[0].prNumber, 700);
  assert.equal(contexts.review[0].waitCommentId, null);
  assert.equal(contexts.waiting.length, 1);
  assert.equal(contexts.waiting[0].taskId, "PL-099-WAIT");
  assert.equal(contexts.waiting[0].issueNumber, 803);
  assert.equal(contexts.waiting[0].waitCommentId, "comment-803");
  assert.equal(contexts.waiting[0].kind, "BLOCKER");
  assert.equal(contexts.waiting[0].pendingPost, false);
});

test("primary contexts expose review feedback anchor metadata", async () => {
  const store = createAiFlowV2StateStore({
    adapter: createMemoryAdapter(),
  });
  await store.init();

  await store.putTask({ id: "PL-100-REVIEW", title: "review feedback", repo: "justewg/planka", issueNumber: 804 });
  await store.putTaskState({
    taskId: "PL-100-REVIEW",
    phase: "reviewing",
    reason: "awaiting review",
    ownerMode: "human",
    canonicalReviewPrNumber: 710,
    canonicalWaitCommentId: "comment-804",
    updatedAt: "2026-03-28T19:33:00.000Z",
    meta: {
      reviewFeedback: {
        commentUrl: "https://github.com/justewg/planka/issues/804#issuecomment-2",
        pendingPost: true,
        waitingSince: "2026-03-28T19:33:00.000Z",
      },
    },
  });

  const contexts = await derivePrimaryContexts(store);
  assert.equal(contexts.review.length, 1);
  assert.equal(contexts.review[0].taskId, "PL-100-REVIEW");
  assert.equal(contexts.review[0].waitCommentId, "comment-804");
  assert.equal(contexts.review[0].commentUrl, "https://github.com/justewg/planka/issues/804#issuecomment-2");
  assert.equal(contexts.review[0].pendingPost, true);
});
