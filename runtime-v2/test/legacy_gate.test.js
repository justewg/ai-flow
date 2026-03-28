"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const os = require("os");
const path = require("path");

const {
  createAiFlowV2StateStore,
  createMemoryAdapter,
  syncLegacyShadowSnapshot,
  evaluateLegacyPolicyGate,
} = require("../src");

test("legacy shadow sync imports execution ledger and preserves stronger budget stop", async () => {
  const stateDir = fs.mkdtempSync(path.join(os.tmpdir(), "aiflow-v2-ledger-"));
  const store = createAiFlowV2StateStore({
    adapter: createMemoryAdapter(),
  });
  await store.init();

  await store.putTask({ id: "PL-096", title: "gate", repo: "justewg/planka" });
  await store.putTaskState({
    taskId: "PL-096",
    phase: "paused",
    reason: "manual freeze",
    ownerMode: "human",
    budgetState: "emergency_stop",
    lockState: "frozen",
  });

  fs.writeFileSync(
    path.join(stateDir, "execution_ledger.jsonl"),
    `${JSON.stringify({
      taskId: "PL-096",
      issueNumber: "600",
      rc: "0",
      startedAt: "2026-03-28T12:00:00.000Z",
      finishedAt: "2026-03-28T12:05:00.000Z",
      terminationReason: "completed",
      providerErrorClass: "none",
      detached: false,
      controlMode: "AUTO",
    })}\n`,
  );

  const sync = await syncLegacyShadowSnapshot(store, stateDir, {
    repo: "justewg/planka",
  });

  assert.equal(sync.syncedTasks.length, 1);
  const bundle = await store.getTaskBundle("PL-096");
  assert.equal(bundle.task.issueNumber, 600);
  assert.equal(bundle.taskState.budgetState, "emergency_stop");
  assert.equal(bundle.taskState.lockState, "frozen");

  const executions = await store.listTaskExecutions("PL-096");
  assert.equal(executions.length, 1);
  assert.equal(executions[0].status, "succeeded");
  assert.equal(executions[0].sideEffectClass, "expensive_ai");
});

test("legacy policy gate blocks expensive paths during shadow rollout", async () => {
  const stateDir = fs.mkdtempSync(path.join(os.tmpdir(), "aiflow-v2-gate-shadow-"));
  const store = createAiFlowV2StateStore({
    adapter: createMemoryAdapter(),
  });
  await store.init();

  const verdict = await evaluateLegacyPolicyGate(store, {
    legacyStateDir: stateDir,
    repo: "justewg/planka",
    taskId: "PL-096-SHADOW",
    issueNumber: "601",
    gateName: "daemon_claim",
    rolloutMode: "shadow",
    allowedTaskIds: [],
    sideEffectClass: "state_only",
    expensive: true,
    staleCheck: false,
    maxExecutionsPerTask: 3,
    maxTokenUsagePerTask: 60000,
    maxEstimatedCostPerTask: 25,
    emergencyOnBreach: true,
  });

  assert.equal(verdict.status, "blocked");
  assert.equal(verdict.reason, "rollout_shadow_blocks_side_effects");
});

test("legacy policy gate blocks watchdog recovery when active execution is stale in v2 shadow", async () => {
  const stateDir = fs.mkdtempSync(path.join(os.tmpdir(), "aiflow-v2-gate-stale-"));
  fs.writeFileSync(path.join(stateDir, "executor_task_id.txt"), "PL-096-WD\n");
  fs.writeFileSync(path.join(stateDir, "executor_issue_number.txt"), "602\n");
  fs.writeFileSync(path.join(stateDir, "executor_state.txt"), "RUNNING\n");

  const store = createAiFlowV2StateStore({
    adapter: createMemoryAdapter(),
  });
  await store.init();

  const verdict = await evaluateLegacyPolicyGate(store, {
    legacyStateDir: stateDir,
    repo: "justewg/planka",
    taskId: "PL-096-WD",
    issueNumber: "602",
    gateName: "watchdog_MEDIUM_RESET_EXECUTOR",
    rolloutMode: "single_task",
    allowedTaskIds: ["PL-096-WD"],
    sideEffectClass: "state_only",
    expensive: true,
    staleCheck: true,
    maxExecutionsPerTask: 3,
    maxTokenUsagePerTask: 60000,
    maxEstimatedCostPerTask: 25,
    emergencyOnBreach: true,
  });

  assert.equal(verdict.status, "blocked");
  assert.equal(verdict.reason, "stale_execution_detected");
});
