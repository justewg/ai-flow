#!/usr/bin/env node
"use strict";

const path = require("path");

const {
  createAiFlowV2StateStore,
  createFileAdapter,
  deriveGlobalControlMode,
} = require("../src");

function parseArgs(argv) {
  const args = {
    storeDir: "",
  };

  for (let index = 2; index < argv.length; index += 1) {
    const token = argv[index];
    const next = argv[index + 1];
    if (token === "--store-dir") {
      args.storeDir = next;
      index += 1;
    }
  }

  if (!args.storeDir) {
    throw new Error("Usage: runtime_v2_control_mode.js --store-dir <dir>");
  }
  return args;
}

async function main() {
  const args = parseArgs(process.argv);
  const store = createAiFlowV2StateStore({
    adapter: createFileAdapter({ storeDir: path.resolve(args.storeDir) }),
  });
  await store.init();
  const taskStates = await store.listTaskStates();
  const result = deriveGlobalControlMode(taskStates);
  console.log(JSON.stringify(result, null, 2));
}

main().catch((error) => {
  console.error(error && error.stack ? error.stack : String(error));
  process.exit(1);
});
