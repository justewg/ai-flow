#!/usr/bin/env node
"use strict";

const path = require("path");

const {
  createAiFlowV2StateStore,
  createFileAdapter,
} = require("../src");
const { syncLegacyShadowSnapshot } = require("../src");

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

  const sync = await syncLegacyShadowSnapshot(store, legacyStateDir, { repo });

  console.log(
    JSON.stringify(
      {
        syncedTaskCount: sync.syncedTasks.length,
        syncedTasks: sync.syncedTasks,
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
