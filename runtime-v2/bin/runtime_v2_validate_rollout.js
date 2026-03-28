#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");

const {
  createAiFlowV2StateStore,
  createFileAdapter,
  runRolloutValidation,
} = require("../src");

function parseArgs(argv) {
  const args = {
    storeDir: "",
    legacyStateDir: "",
    repo: "unknown/repo",
    taskId: "PL-104-VALIDATION",
    issueNumber: 104,
    outputFile: "",
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
    } else if (token === "--repo") {
      args.repo = next;
      index += 1;
    } else if (token === "--task-id") {
      args.taskId = next;
      index += 1;
    } else if (token === "--issue-number") {
      args.issueNumber = Number(next || "104");
      index += 1;
    } else if (token === "--output-file") {
      args.outputFile = next;
      index += 1;
    } else if (token === "--compact") {
      args.compact = true;
    }
  }

  if (!args.storeDir || !args.legacyStateDir) {
    throw new Error(
      "Usage: runtime_v2_validate_rollout.js --legacy-state-dir <dir> --store-dir <dir> [--repo <owner/repo>] [--task-id <id>] [--issue-number <n>] [--output-file <file>] [--compact]",
    );
  }
  if (!Number.isInteger(args.issueNumber) || args.issueNumber < 1) {
    throw new Error("--issue-number must be a positive integer");
  }

  return args;
}

async function main() {
  const args = parseArgs(process.argv);
  const store = createAiFlowV2StateStore({
    adapter: createFileAdapter({ storeDir: path.resolve(args.storeDir) }),
  });
  await store.init();

  const report = await runRolloutValidation(store, {
    legacyStateDir: path.resolve(args.legacyStateDir),
    storeDir: path.resolve(args.storeDir),
    repo: args.repo,
    taskId: args.taskId,
    issueNumber: args.issueNumber,
  });

  const output = `${JSON.stringify(report, null, args.compact ? 0 : 2)}\n`;
  if (args.outputFile) {
    fs.mkdirSync(path.dirname(path.resolve(args.outputFile)), { recursive: true });
    fs.writeFileSync(path.resolve(args.outputFile), output, "utf8");
  }
  process.stdout.write(output);
  if (!report.ok) {
    process.exitCode = 2;
  }
}

main().catch((error) => {
  console.error(error && error.stack ? error.stack : String(error));
  process.exit(1);
});
