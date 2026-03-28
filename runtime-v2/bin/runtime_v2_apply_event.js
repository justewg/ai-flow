#!/usr/bin/env node
"use strict";

const path = require("path");

const {
  createAiFlowV2StateStore,
  createFileAdapter,
  applyLegacyEventBridge,
} = require("../src");

function parseArgs(argv) {
  const args = {
    legacyStateDir: "",
    storeDir: "",
    repo: "",
    taskId: "",
    issueNumber: "",
    eventType: "",
    eventId: "",
    source: "runtime_v2_event_bridge",
    dedupKey: "",
    payloadJson: "{}",
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
    } else if (token === "--task-id") {
      args.taskId = next;
      index += 1;
    } else if (token === "--issue-number") {
      args.issueNumber = next;
      index += 1;
    } else if (token === "--event-type") {
      args.eventType = next;
      index += 1;
    } else if (token === "--event-id") {
      args.eventId = next;
      index += 1;
    } else if (token === "--source") {
      args.source = next;
      index += 1;
    } else if (token === "--dedup-key") {
      args.dedupKey = next;
      index += 1;
    } else if (token === "--payload-json") {
      args.payloadJson = next;
      index += 1;
    }
  }

  if (!args.legacyStateDir || !args.storeDir || !args.repo || !args.taskId || !args.eventType) {
    throw new Error(
      "Usage: runtime_v2_apply_event.js --legacy-state-dir <dir> --store-dir <dir> --repo <owner/repo> --task-id <id> --event-type <type> [--issue-number <n>] [--event-id <id>] [--dedup-key <key>] [--payload-json <json>]",
    );
  }
  return args;
}

async function main() {
  const args = parseArgs(process.argv);
  const payload = JSON.parse(args.payloadJson || "{}");
  const store = createAiFlowV2StateStore({
    adapter: createFileAdapter({ storeDir: path.resolve(args.storeDir) }),
  });
  await store.init();

  const result = await applyLegacyEventBridge(store, {
    legacyStateDir: path.resolve(args.legacyStateDir),
    repo: args.repo,
    taskId: args.taskId,
    issueNumber: args.issueNumber,
    eventType: args.eventType,
    eventId: args.eventId,
    source: args.source,
    dedupKey: args.dedupKey,
    payload,
  });

  console.log(JSON.stringify(result, null, 2));
}

main().catch((error) => {
  console.error(error && error.stack ? error.stack : String(error));
  process.exit(1);
});
