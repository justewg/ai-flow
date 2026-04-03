#!/usr/bin/env node
"use strict";

const path = require("path");

const {
  createAiFlowV2StateStore,
  createFileAdapter,
  evaluateLegacyPolicyGate,
} = require("../src");

function parseBoolean(value, fallback = false) {
  if (value === undefined || value === null || value === "") {
    return fallback;
  }
  return ["1", "true", "yes", "on"].includes(String(value).trim().toLowerCase());
}

function parseInteger(value, fallback) {
  const parsed = Number.parseInt(String(value || ""), 10);
  return Number.isInteger(parsed) ? parsed : fallback;
}

function parseNumber(value, fallback) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function parseCsv(value) {
  if (!value) {
    return [];
  }
  return String(value)
    .split(",")
    .map((token) => token.trim())
    .filter(Boolean);
}

function parseArgs(argv) {
  const args = {
    legacyStateDir: "",
    storeDir: "",
    repo: "",
    taskId: "",
    issueNumber: "",
    gateName: "",
    rolloutMode: process.env.FLOW_V2_ROLLOUT_MODE || "shadow",
    allowedTaskIds: parseCsv(process.env.FLOW_V2_ALLOWED_TASK_IDS || ""),
    sideEffectClass: "state_only",
    expensive: false,
    staleCheck: false,
    maxExecutionsPerTask: parseInteger(process.env.FLOW_V2_MAX_EXECUTIONS_PER_TASK, 3),
    maxTokenUsagePerTask: parseInteger(process.env.FLOW_V2_MAX_TOKEN_USAGE_PER_TASK, 60000),
    maxEstimatedCostPerTask: parseNumber(process.env.FLOW_V2_MAX_ESTIMATED_COST_PER_TASK, 25),
    emergencyOnBreach: parseBoolean(process.env.FLOW_V2_EMERGENCY_ON_BREACH, true),
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
    } else if (token === "--gate-name") {
      args.gateName = next;
      index += 1;
    } else if (token === "--rollout-mode") {
      args.rolloutMode = next;
      index += 1;
    } else if (token === "--allowed-task-ids") {
      args.allowedTaskIds = parseCsv(next);
      index += 1;
    } else if (token === "--side-effect-class") {
      args.sideEffectClass = next;
      index += 1;
    } else if (token === "--expensive") {
      args.expensive = parseBoolean(next, true);
      index += 1;
    } else if (token === "--stale-check") {
      args.staleCheck = parseBoolean(next, true);
      index += 1;
    } else if (token === "--max-executions-per-task") {
      args.maxExecutionsPerTask = parseInteger(next, 3);
      index += 1;
    } else if (token === "--max-token-usage-per-task") {
      args.maxTokenUsagePerTask = parseInteger(next, 60000);
      index += 1;
    } else if (token === "--max-estimated-cost-per-task") {
      args.maxEstimatedCostPerTask = parseNumber(next, 25);
      index += 1;
    } else if (token === "--emergency-on-breach") {
      args.emergencyOnBreach = parseBoolean(next, true);
      index += 1;
    }
  }

  if (!args.legacyStateDir || !args.storeDir || !args.repo || !args.taskId || !args.gateName) {
    throw new Error(
      "Usage: runtime_v2_gate.js --legacy-state-dir <dir> --store-dir <dir> --repo <owner/repo> --task-id <id> --gate-name <name> [--issue-number <n>]",
    );
  }
  return args;
}

async function main() {
  const args = parseArgs(process.argv);
  const store = createAiFlowV2StateStore({
    adapter: createFileAdapter({ storeDir: path.resolve(args.storeDir) }),
  });
  await store.init();

  const verdict = await evaluateLegacyPolicyGate(store, {
    legacyStateDir: path.resolve(args.legacyStateDir),
    repo: args.repo,
    taskId: args.taskId,
    issueNumber: args.issueNumber,
    gateName: args.gateName,
    rolloutMode: args.rolloutMode,
    allowedTaskIds: args.allowedTaskIds,
    sideEffectClass: args.sideEffectClass,
    expensive: args.expensive,
    staleCheck: args.staleCheck,
    maxExecutionsPerTask: args.maxExecutionsPerTask,
    maxTokenUsagePerTask: args.maxTokenUsagePerTask,
    maxEstimatedCostPerTask: args.maxEstimatedCostPerTask,
    emergencyOnBreach: args.emergencyOnBreach,
  });

  console.log(JSON.stringify(verdict, null, 2));
}

main().catch((error) => {
  console.error(error && error.stack ? error.stack : String(error));
  process.exit(1);
});
