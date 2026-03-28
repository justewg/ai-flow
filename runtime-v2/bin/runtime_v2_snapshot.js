#!/usr/bin/env node
"use strict";

const path = require("path");

const {
  createAiFlowV2StateStore,
  createFileAdapter,
} = require("../src");

function parseArgs(argv) {
  const args = {
    storeDir: "",
    taskId: "",
  };
  for (let index = 2; index < argv.length; index += 1) {
    const token = argv[index];
    const next = argv[index + 1];
    if (token === "--store-dir") {
      args.storeDir = next;
      index += 1;
    } else if (token === "--task-id") {
      args.taskId = next;
      index += 1;
    }
  }
  if (!args.storeDir) {
    throw new Error("Usage: runtime_v2_snapshot.js --store-dir <dir> [--task-id <taskId>]");
  }
  return args;
}

async function main() {
  const args = parseArgs(process.argv);
  const store = createAiFlowV2StateStore({
    adapter: createFileAdapter({ storeDir: path.resolve(args.storeDir) }),
  });
  await store.init();

  if (args.taskId) {
    console.log(JSON.stringify(await store.getTaskBundle(args.taskId), null, 2));
    return;
  }

  const tasks = Object.keys(require("fs").existsSync(path.join(path.resolve(args.storeDir), "tasks.json"))
    ? JSON.parse(require("fs").readFileSync(path.join(path.resolve(args.storeDir), "tasks.json"), "utf8"))
    : {});

  const bundles = [];
  for (const taskId of tasks) {
    bundles.push(await store.getTaskBundle(taskId));
  }
  console.log(JSON.stringify({ tasks: bundles }, null, 2));
}

main().catch((error) => {
  console.error(error && error.stack ? error.stack : String(error));
  process.exit(1);
});
