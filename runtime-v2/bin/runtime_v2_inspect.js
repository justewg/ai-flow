#!/usr/bin/env node
"use strict";

const path = require("path");

const {
  createAiFlowV2StateStore,
  createFileAdapter,
  buildInspectionSummary,
} = require("../src");

function parseArgs(argv) {
  const args = {
    storeDir: "",
    legacyStateDir: "",
    maxRecent: 10,
    compact: false,
  };

  for (let index = 2; index < argv.length; index += 1) {
    const token = argv[index];
    const next = argv[index + 1];
    if (token === "--store-dir") {
      args.storeDir = next;
      index += 1;
    } else if (token === "--legacy-state-dir") {
      args.legacyStateDir = next;
      index += 1;
    } else if (token === "--max-recent") {
      args.maxRecent = Number(next || "10");
      index += 1;
    } else if (token === "--compact") {
      args.compact = true;
    }
  }

  if (!args.storeDir || !args.legacyStateDir) {
    throw new Error("Usage: runtime_v2_inspect.js --legacy-state-dir <dir> --store-dir <dir> [--max-recent <n>] [--compact]");
  }
  if (!Number.isInteger(args.maxRecent) || args.maxRecent < 1) {
    throw new Error("--max-recent must be a positive integer");
  }
  return args;
}

async function main() {
  const args = parseArgs(process.argv);
  const store = createAiFlowV2StateStore({
    adapter: createFileAdapter({ storeDir: path.resolve(args.storeDir) }),
  });
  await store.init();

  const summary = await buildInspectionSummary({
    store,
    legacyStateDir: path.resolve(args.legacyStateDir),
    storeDir: path.resolve(args.storeDir),
    maxRecent: args.maxRecent,
  });

  console.log(JSON.stringify(summary, null, args.compact ? 0 : 2));
}

main().catch((error) => {
  console.error(error && error.stack ? error.stack : String(error));
  process.exit(1);
});
