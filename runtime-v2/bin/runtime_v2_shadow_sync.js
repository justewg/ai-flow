#!/usr/bin/env node
"use strict";

const path = require("path");

const {
  createAiFlowV2StateStore,
  createFileAdapter,
} = require("../src");
const {
  collectLegacyShadowSnapshot,
  inferTaskStateFromLegacy,
  buildSnapshotHash,
} = require("../src/legacy_shadow");

function parseArgs(argv) {
  const args = {
    legacyStateDir: "",
    storeDir: "",
    repo: "",
  };
  for (let index = 2; index < argv.length; index += 1) {
    const token = argv[index];
    const next = argv[index + 1];
    if (token === "--legacy-state-dir") {
      args.legacyStateDir = next;
      index += 1;
    } else if (token === "--store-dir") {
      args.storeDir = next;
      index += 1;
    } else if (token === "--repo") {
      args.repo = next;
      index += 1;
    }
  }
  if (!args.legacyStateDir || !args.storeDir) {
    throw new Error("Usage: runtime_v2_shadow_sync.js --legacy-state-dir <dir> --store-dir <dir> [--repo <owner/repo>]");
  }
  return args;
}

async function main() {
  const args = parseArgs(process.argv);
  const legacyStateDir = path.resolve(args.legacyStateDir);
  const storeDir = path.resolve(args.storeDir);
  const repo = args.repo || process.env.FLOW_GITHUB_REPO || "unknown/repo";

  const store = createAiFlowV2StateStore({
    adapter: createFileAdapter({ storeDir }),
  });
  await store.init();

  const { snapshot, taskIds } = collectLegacyShadowSnapshot(legacyStateDir);
  const syncedTasks = [];

  for (const taskId of taskIds) {
    const taskStateProjection = inferTaskStateFromLegacy(taskId, snapshot);
    const issueNumberRaw =
      snapshot.daemonWaitingTaskId === taskId
        ? snapshot.daemonWaitingIssueNumber
        : snapshot.daemonReviewTaskId === taskId
          ? snapshot.daemonReviewIssueNumber
          : snapshot.executorTaskId === taskId
            ? snapshot.executorIssueNumber
            : snapshot.daemonActiveTask === taskId
              ? snapshot.daemonActiveIssueNumber
              : "";
    const issueNumber = Number.parseInt(issueNumberRaw || "", 10);

    await store.putTask({
      id: taskId,
      title: `Legacy shadow task ${taskId}`,
      repo,
      issueNumber: Number.isInteger(issueNumber) && issueNumber > 0 ? issueNumber : null,
      meta: {
        legacyShadow: true,
      },
    });

    await store.putTaskState({
      taskId,
      ...taskStateProjection,
      reason: `${taskStateProjection.reason}${snapshot.controlReason ? ` (${snapshot.controlReason})` : ""}`,
      meta: {
        source: "legacy_shadow_sync_v2",
      },
    });

    if (taskStateProjection.activeExecutionId) {
      await store.putExecution({
        id: taskStateProjection.activeExecutionId,
        taskId,
        triggerEventId: `legacy-shadow-trigger-${taskId}`,
        executionType: "reconcile",
        phase: "executing",
        dedupKey: `legacy-shadow-execution:${taskId}`,
        status: "running",
        inputHash: `legacy-shadow:${taskId}`,
        sideEffectClass: "state_only",
      });
    }

    const snapshotHash = buildSnapshotHash({
      taskId,
      taskStateProjection,
      issueNumber: Number.isInteger(issueNumber) && issueNumber > 0 ? issueNumber : null,
      controlMode: snapshot.controlMode,
    });
    const dedupKey = `legacy_shadow_snapshot:${taskId}:${snapshotHash}`;
    const existing = await store.findEventByDedupKey(taskId, dedupKey);
    if (!existing) {
      await store.appendEvent({
        id: `legacy-shadow-event-${taskId}-${snapshotHash}`,
        taskId,
        eventType: "legacy.shadow_synced",
        source: "runtime_v2_shadow_sync",
        dedupKey,
        payload: {
          controlMode: snapshot.controlMode,
          issueNumber: Number.isInteger(issueNumber) && issueNumber > 0 ? issueNumber : null,
          taskStateProjection,
        },
      });
    }

    const bundle = await store.getTaskBundle(taskId);
    syncedTasks.push({
      taskId,
      phase: bundle.taskState ? bundle.taskState.phase : null,
      reviewPr: bundle.canonicalReviewPrNumber,
      waitingCommentId: bundle.canonicalWaitCommentId,
      activeExecutionId: bundle.activeExecution ? bundle.activeExecution.id : null,
    });
  }

  console.log(
    JSON.stringify(
      {
        syncedTaskCount: syncedTasks.length,
        syncedTasks,
        storeDir,
      },
      null,
      2,
    ),
  );
}

main().catch((error) => {
  console.error(error && error.stack ? error.stack : String(error));
  process.exit(1);
});
