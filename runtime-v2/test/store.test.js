"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  createAiFlowV2StateStore,
  createMemoryAdapter,
  applyEvent,
  acquireExecutionLease,
  heartbeatExecutionLease,
  evaluateExecutionStaleness,
  markExecutionStale,
  evaluateTaskBudget,
  enforceTaskBudget,
  evaluateRolloutGate,
  evaluateAutomationGate,
  deriveGlobalControlMode,
  parseMongoConfig,
  normalizeExecution,
  ValidationError,
  ConfigError,
} = require("../src");

test("memory store returns task bundle with state and active execution", async () => {
  const store = createAiFlowV2StateStore({
    adapter: createMemoryAdapter(),
  });
  await store.init();

  await store.putTask({
    id: "PL-091",
    title: "State store bootstrap",
    repo: "justewg/planka",
    issueNumber: 9001,
  });

  await store.putExecution({
    id: "exec-1",
    taskId: "PL-091",
    triggerEventId: "event-1",
    executionType: "plan",
    phase: "planned",
    dedupKey: "dedup-1",
    status: "running",
    inputHash: "hash-1",
    sideEffectClass: "expensive_ai",
  });

  await store.putTaskState({
    taskId: "PL-091",
    phase: "executing",
    reason: "bootstrap validation",
    ownerMode: "human",
    activeExecutionId: "exec-1",
    canonicalReviewPrNumber: 518,
    canonicalWaitCommentId: "comment-1",
  });

  await store.appendEvent({
    id: "event-1",
    taskId: "PL-091",
    eventType: "task.created",
    source: "test",
    payload: { phase: "planned" },
  });

  const bundle = await store.getTaskBundle("PL-091");
  assert.equal(bundle.task.id, "PL-091");
  assert.equal(bundle.taskState.phase, "executing");
  assert.equal(bundle.activeExecution.id, "exec-1");
  assert.equal(bundle.canonicalReviewPrNumber, 518);
  assert.equal(bundle.events.length, 1);
});

test("normalizeExecution rejects invalid status", () => {
  assert.throws(
    () =>
      normalizeExecution({
        id: "exec-2",
        taskId: "PL-091",
        triggerEventId: "event-2",
        executionType: "plan",
        phase: "planned",
        dedupKey: "dedup-2",
        status: "weird",
        inputHash: "hash-2",
        sideEffectClass: "expensive_ai",
      }),
    ValidationError,
  );
});

test("parseMongoConfig validates required env", () => {
  assert.throws(() => parseMongoConfig({}), ConfigError);

  const config = parseMongoConfig({
    AIFLOW_V2_MONGODB_URI: "mongodb://127.0.0.1:27017",
    AIFLOW_V2_MONGODB_DB: "aiflow_v2_dev",
  });

  assert.equal(config.uri, "mongodb://127.0.0.1:27017");
  assert.equal(config.dbName, "aiflow_v2_dev");
  assert.equal(config.collectionPrefix, "aiflow_v2");
});

test("review.finalized creates canonical review artifact and repeated finalize becomes noop", async () => {
  const store = createAiFlowV2StateStore({
    adapter: createMemoryAdapter(),
  });
  await store.init();
  await store.putTask({ id: "PL-092", title: "orchestrator", repo: "justewg/planka" });
  await store.putTaskState({
    taskId: "PL-092",
    phase: "ready",
    reason: "ready for finalize",
    ownerMode: "human",
  });

  const first = await applyEvent(store, {
    id: "event-review-1",
    taskId: "PL-092",
    eventType: "review.finalized",
    source: "test",
    dedupKey: "review-1",
    payload: { prNumber: 518, waitCommentId: "comment-518" },
  });
  assert.equal(first.status, "applied");

  const duplicate = await applyEvent(store, {
    id: "event-review-1b",
    taskId: "PL-092",
    eventType: "review.finalized",
    source: "test",
    dedupKey: "review-1",
    payload: { prNumber: 518, waitCommentId: "comment-518" },
  });
  assert.equal(duplicate.status, "noop");
  assert.equal(duplicate.reason, "duplicate_event");

  const conflicting = await applyEvent(store, {
    id: "event-review-2",
    taskId: "PL-092",
    eventType: "review.finalized",
    source: "test",
    payload: { prNumber: 519, waitCommentId: "comment-519" },
  });
  assert.equal(conflicting.status, "noop");
  assert.equal(conflicting.reason, "canonical_review_pr_exists");
});

test("WAIT_HUMAN is terminal for expensive execution until human response", async () => {
  const store = createAiFlowV2StateStore({
    adapter: createMemoryAdapter(),
  });
  await store.init();
  await store.putTask({ id: "PL-092-WAIT", title: "wait", repo: "justewg/planka" });
  await store.putTaskState({
    taskId: "PL-092-WAIT",
    phase: "ready",
    reason: "ready",
    ownerMode: "human",
  });

  const waitResult = await applyEvent(store, {
    id: "event-wait-1",
    taskId: "PL-092-WAIT",
    eventType: "human.wait_requested",
    source: "test",
    payload: { waitCommentId: "comment-wait-1", reason: "need answer" },
  });
  assert.equal(waitResult.status, "applied");

  const blockedRun = await applyEvent(store, {
    id: "event-run-1",
    taskId: "PL-092-WAIT",
    eventType: "execution.started",
    source: "test",
    payload: { executionId: "exec-wait-1" },
  });
  assert.equal(blockedRun.status, "blocked");
  assert.equal(blockedRun.reason, "waiting_human_terminal");

  const resume = await applyEvent(store, {
    id: "event-human-1",
    taskId: "PL-092-WAIT",
    eventType: "human.response_received",
    source: "test",
    payload: { responseType: "resume" },
  });
  assert.equal(resume.status, "applied");

  const runAfterResume = await applyEvent(store, {
    id: "event-run-2",
    taskId: "PL-092-WAIT",
    eventType: "execution.started",
    source: "test",
    payload: { executionId: "exec-wait-2" },
  });
  assert.equal(runAfterResume.status, "applied");
  assert.equal(runAfterResume.taskState.phase, "executing");
});

test("orchestrator blocks second active execution", async () => {
  const store = createAiFlowV2StateStore({
    adapter: createMemoryAdapter(),
  });
  await store.init();
  await store.putTask({ id: "PL-092-EXEC", title: "active execution invariant", repo: "justewg/planka" });
  await store.putTaskState({
    taskId: "PL-092-EXEC",
    phase: "executing",
    reason: "exec 1 running",
    ownerMode: "human",
    activeExecutionId: "exec-1",
  });

  const secondRun = await applyEvent(store, {
    id: "event-exec-2",
    taskId: "PL-092-EXEC",
    eventType: "execution.started",
    source: "test",
    payload: { executionId: "exec-2" },
  });
  assert.equal(secondRun.status, "blocked");
  assert.equal(secondRun.reason, "active_execution_exists");
});

test("execution lease acquisition dedups identical expensive run", async () => {
  const store = createAiFlowV2StateStore({
    adapter: createMemoryAdapter(),
  });
  await store.init();
  await store.putTask({ id: "PL-093", title: "lease", repo: "justewg/planka" });
  await store.putTaskState({
    taskId: "PL-093",
    phase: "ready",
    reason: "ready for execution",
    ownerMode: "human",
  });

  const first = await acquireExecutionLease(store, {
    id: "exec-lease-1",
    taskId: "PL-093",
    triggerEventId: "event-lease-1",
    executionType: "implement",
    phase: "executing",
    inputHash: "hash-lease-1",
    sideEffectClass: "expensive_ai",
  });
  assert.equal(first.status, "applied");

  const second = await acquireExecutionLease(store, {
    id: "exec-lease-2",
    taskId: "PL-093",
    triggerEventId: "event-lease-1",
    executionType: "implement",
    phase: "executing",
    inputHash: "hash-lease-1",
    sideEffectClass: "expensive_ai",
  });
  assert.equal(second.status, "noop");
  assert.equal(second.reason, "duplicate_execution_dedup");
});

test("heartbeat refreshes lease and stale execution can be marked failed without restart", async () => {
  const store = createAiFlowV2StateStore({
    adapter: createMemoryAdapter(),
  });
  await store.init();
  await store.putTask({ id: "PL-093-STALE", title: "stale", repo: "justewg/planka" });
  await store.putTaskState({
    taskId: "PL-093-STALE",
    phase: "ready",
    reason: "ready for execution",
    ownerMode: "human",
  });

  const acquired = await acquireExecutionLease(
    store,
    {
      id: "exec-stale-1",
      taskId: "PL-093-STALE",
      triggerEventId: "event-stale-1",
      executionType: "implement",
      phase: "executing",
      inputHash: "hash-stale-1",
      sideEffectClass: "expensive_ai",
    },
    {
      now: "2026-03-28T18:00:00.000Z",
      leaseDurationSec: 60,
    },
  );
  assert.equal(acquired.status, "applied");

  const heartbeat = await heartbeatExecutionLease(store, "exec-stale-1", {
    now: "2026-03-28T18:00:30.000Z",
    leaseDurationSec: 60,
  });
  assert.equal(heartbeat.status, "applied");

  const healthy = await evaluateExecutionStaleness(store, "exec-stale-1", {
    now: "2026-03-28T18:01:00.000Z",
  });
  assert.equal(healthy.status, "healthy");

  const stale = await evaluateExecutionStaleness(store, "exec-stale-1", {
    now: "2026-03-28T18:01:31.000Z",
  });
  assert.equal(stale.status, "stale");

  const marked = await markExecutionStale(store, "exec-stale-1", {
    now: "2026-03-28T18:01:31.000Z",
  });
  assert.equal(marked.status, "applied");
  assert.equal(marked.execution.status, "failed");
  assert.equal(marked.execution.terminationReason, "stale_execution");

  const repeat = await markExecutionStale(store, "exec-stale-1", {
    now: "2026-03-28T18:02:00.000Z",
  });
  assert.equal(repeat.status, "noop");
  assert.equal(repeat.reason, "execution_not_running");
});

test("budget breach moves task into emergency stop", async () => {
  const store = createAiFlowV2StateStore({
    adapter: createMemoryAdapter(),
  });
  await store.init();
  await store.putTask({ id: "PL-094", title: "budget", repo: "justewg/planka" });
  await store.putTaskState({
    taskId: "PL-094",
    phase: "ready",
    reason: "budget validation",
    ownerMode: "human",
  });
  await store.putExecution({
    id: "exec-budget-1",
    taskId: "PL-094",
    triggerEventId: "evt-budget-1",
    executionType: "implement",
    phase: "executing",
    dedupKey: "dedup-budget-1",
    status: "succeeded",
    inputHash: "hash-budget-1",
    sideEffectClass: "expensive_ai",
    tokenUsage: 1000,
  });
  await store.putExecution({
    id: "exec-budget-2",
    taskId: "PL-094",
    triggerEventId: "evt-budget-2",
    executionType: "implement",
    phase: "executing",
    dedupKey: "dedup-budget-2",
    status: "failed",
    inputHash: "hash-budget-2",
    sideEffectClass: "expensive_ai",
    tokenUsage: 1000,
  });

  const budget = await evaluateTaskBudget(store, "PL-094", {
    maxExecutionsPerTask: 1,
  });
  assert.equal(budget.status, "breach");

  const enforced = await enforceTaskBudget(store, "PL-094", {
    maxExecutionsPerTask: 1,
  });
  assert.equal(enforced.status, "blocked");
  assert.equal(enforced.taskState.budgetState, "emergency_stop");
  assert.equal(enforced.taskState.lockState, "frozen");
});

test("rollout gate only allows configured modes", () => {
  const dryRun = evaluateRolloutGate({
    rolloutMode: "dry_run",
    taskId: "PL-094",
    expensive: true,
    sideEffectClass: "expensive_ai",
  });
  assert.equal(dryRun.status, "blocked");
  assert.equal(dryRun.reason, "rollout_dry_run");

  const singleAllowed = evaluateRolloutGate({
    rolloutMode: "single_task",
    taskId: "PL-094",
    allowedTaskIds: ["PL-094"],
    expensive: true,
    sideEffectClass: "expensive_ai",
  });
  assert.equal(singleAllowed.status, "applied");

  const singleDenied = evaluateRolloutGate({
    rolloutMode: "single_task",
    taskId: "PL-999",
    allowedTaskIds: ["PL-094"],
    expensive: true,
    sideEffectClass: "expensive_ai",
  });
  assert.equal(singleDenied.status, "blocked");
  assert.equal(singleDenied.reason, "rollout_single_task_denied");
});

test("automation gate blocks tasks already stopped by budget", async () => {
  const store = createAiFlowV2StateStore({
    adapter: createMemoryAdapter(),
  });
  await store.init();
  await store.putTask({ id: "PL-094-GATE", title: "gate", repo: "justewg/planka" });
  await store.putTaskState({
    taskId: "PL-094-GATE",
    phase: "paused",
    reason: "budget breach",
    ownerMode: "human",
    budgetState: "emergency_stop",
    lockState: "frozen",
  });

  const gate = await evaluateAutomationGate(store, "PL-094-GATE", {
    rolloutMode: "limited",
    allowedTaskIds: ["PL-094-GATE"],
    expensive: true,
    sideEffectClass: "expensive_ai",
  });
  assert.equal(gate.status, "blocked");
  assert.equal(gate.reason, "task_budget_stopped");
});

test("budget.breached moves task into emergency stop state", async () => {
  const store = createAiFlowV2StateStore({
    adapter: createMemoryAdapter(),
  });
  await store.init();
  await store.putTask({ id: "PL-102", title: "budget breach", repo: "justewg/planka" });
  await store.putTaskState({
    taskId: "PL-102",
    phase: "executing",
    reason: "running",
    ownerMode: "human",
    activeExecutionId: "exec-102",
  });

  const result = await applyEvent(store, {
    id: "event-budget-1",
    taskId: "PL-102",
    eventType: "budget.breached",
    source: "test",
    payload: {
      reason: "provider quota exceeded during executor run",
      breachReason: "provider_quota_exceeded",
      providerErrorClass: "quota_exceeded",
      budgetState: "emergency_stop",
      triggeredAt: "2026-03-28T21:30:00.000Z",
    },
  });

  assert.equal(result.status, "applied");
  assert.equal(result.taskState.phase, "paused");
  assert.equal(result.taskState.budgetState, "emergency_stop");
  assert.equal(result.taskState.lockState, "frozen");
  assert.equal(result.taskState.meta.budget.providerErrorClass, "quota_exceeded");
});

test("global control mode derives from strongest budget stop", () => {
  const result = deriveGlobalControlMode([
    {
      taskId: "PL-102-A",
      budgetState: "paused_budget",
    },
    {
      taskId: "PL-102-B",
      budgetState: "emergency_stop",
    },
  ]);

  assert.equal(result.mode, "EMERGENCY_STOP");
  assert.equal(result.reason, "runtime_v2_budget_emergency:PL-102-B");
});
