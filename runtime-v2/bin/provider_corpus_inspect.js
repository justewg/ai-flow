#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");

const USAGE = "Usage: provider_corpus_inspect.js --state-dir <path> [--module intake.interpretation] [--shadow-provider claude]";

function parseArgs(argv) {
  const args = {
    stateDir: "",
    module: "intake.interpretation",
    shadowProvider: "claude",
  };

  for (let index = 2; index < argv.length; index += 1) {
    const token = argv[index];
    const next = argv[index + 1];
    if (token === "--state-dir") {
      args.stateDir = next;
      index += 1;
    } else if (token === "--module") {
      args.module = next;
      index += 1;
    } else if (token === "--shadow-provider") {
      args.shadowProvider = next;
      index += 1;
    } else if (token === "-h" || token === "--help") {
      args.help = true;
    } else {
      throw new Error(`Unknown option: ${token}`);
    }
  }

  if (!args.help && !args.stateDir) {
    throw new Error(USAGE);
  }

  return args;
}

function readJson(filePath) {
  if (!filePath || !fs.existsSync(filePath)) {
    return null;
  }
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function readJsonl(filePath) {
  if (!filePath || !fs.existsSync(filePath)) {
    return [];
  }
  const raw = fs.readFileSync(filePath, "utf8").trim();
  if (!raw) {
    return [];
  }
  return raw
    .split(/\n+/)
    .filter(Boolean)
    .map((line) => JSON.parse(line));
}

function findFiles(rootDir, fileName) {
  const result = [];
  if (!fs.existsSync(rootDir)) {
    return result;
  }
  const stack = [rootDir];
  while (stack.length > 0) {
    const current = stack.pop();
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      const fullPath = path.join(current, entry.name);
      if (entry.isDirectory()) {
        stack.push(fullPath);
      } else if (entry.isFile() && entry.name === fileName) {
        result.push(fullPath);
      }
    }
  }
  return result.sort();
}

function latestTelemetryByTask(records, moduleName, shadowProvider) {
  const byTask = new Map();
  for (const record of records) {
    if (record.module !== moduleName || record.shadowProvider !== shadowProvider) {
      continue;
    }
    byTask.set(record.taskId, record);
  }
  return byTask;
}

function compareResponseField(response, fieldName) {
  if (!response || typeof response !== "object") {
    return null;
  }
  return response[fieldName] ?? null;
}

function mismatchReasons(compare) {
  const reasons = [];
  if (compare?.schemaValidPrimary === false) {
    reasons.push("schema_valid_primary");
  }
  if (compare?.schemaValidShadow === false) {
    reasons.push("schema_valid_shadow");
  }
  if (compare?.profileMatch === false) {
    reasons.push("profile");
  }
  if (compare?.targetFilesMatch === false) {
    reasons.push(compare.targetFilesDriftTolerated === true ? "target_files_tolerated" : "target_files");
  }
  if (compare?.humanNeededMatch === false) {
    reasons.push("human_needed");
  }
  return reasons;
}

function issueNumberFromTaskId(taskId) {
  const match = String(taskId || "").match(/ISSUE-(\d+)/);
  return match ? Number.parseInt(match[1], 10) : null;
}

function taskIdFromPath(filePath) {
  const match = String(filePath || "").match(/(?:^|[/-])(ISSUE-\d+)(?:-|\/)/);
  return match ? match[1] : null;
}

function inspectCorpus(args) {
  const stateDir = path.resolve(args.stateDir);
  const taskRoot = path.join(stateDir, "task-worktrees");
  const compareFiles = findFiles(taskRoot, "intake_interpretation_compare.json");
  const telemetry = latestTelemetryByTask(
    readJsonl(path.join(stateDir, "provider_telemetry.jsonl")),
    args.module,
    args.shadowProvider,
  );

  const items = compareFiles.map((compareFile) => {
    const executionDir = path.dirname(compareFile);
    const compare = readJson(compareFile) || {};
    const local = readJson(path.join(executionDir, "intake_interpretation_response.local.json")) || {};
    const shadow = readJson(path.join(executionDir, `intake_interpretation_response.${args.shadowProvider}.json`)) || {};
    const taskId =
      compareResponseField(local, "taskId") ||
      compareResponseField(shadow, "taskId") ||
      taskIdFromPath(compareFile) ||
      path.basename(path.dirname(path.dirname(executionDir)));
    const record = telemetry.get(taskId) || null;

    return {
      taskId,
      issueNumber: issueNumberFromTaskId(taskId) ?? compareResponseField(record, "issueNumber"),
      compareSummary: compare.compareSummary || null,
      mismatchReasons: mismatchReasons(compare),
      profileMatch: compare.profileMatch ?? null,
      targetFilesMatch: compare.targetFilesMatch ?? null,
      targetFilesDriftKind: compare.targetFilesDriftKind ?? null,
      targetFilesDriftTolerated: compare.targetFilesDriftTolerated ?? null,
      humanNeededMatch: compare.humanNeededMatch ?? null,
      schemaValidShadow: compare.schemaValidShadow ?? null,
      local: {
        decision: compare.primaryDecision || local.decision || null,
        reason: local.decisionReason || null,
        files: compare.primaryTargetFiles || local.candidateTargetFiles || [],
        confidence: local.confidence || null,
      },
      shadow: {
        decision: compare.shadowDecision || shadow.decision || null,
        reason: shadow.decisionReason || null,
        files: compare.shadowTargetFiles || shadow.candidateTargetFiles || [],
        confidence: shadow.confidence || null,
        error: compare.shadowError || null,
      },
      telemetry: record
        ? {
            ts: record.ts || null,
            outcome: record.outcome || null,
            tokenUsage: record.tokenUsage ?? null,
            latencyMs: record.latencyMs ?? null,
            estimatedCost: record.estimatedCost ?? null,
          }
        : null,
    };
  });

  items.sort((left, right) => {
    const leftIssue = left.issueNumber ?? Number.MAX_SAFE_INTEGER;
    const rightIssue = right.issueNumber ?? Number.MAX_SAFE_INTEGER;
    return leftIssue - rightIssue || String(left.taskId).localeCompare(String(right.taskId));
  });

  const summary = readJson(path.join(stateDir, "provider_corpus_summary.json"));
  const gate = readJson(path.join(stateDir, "provider_corpus_gate.json"));

  return {
    stateDir,
    module: args.module,
    shadowProvider: args.shadowProvider,
    ready: gate?.ready ?? summary?.gate?.ready ?? null,
    blockingReasons: gate?.blockingReasons || summary?.gate?.blockingReasons || [],
    telemetry: summary?.telemetry || null,
    gateTelemetry: summary?.gateTelemetry || null,
    mismatchCounts: items.reduce((acc, item) => {
      for (const reason of item.mismatchReasons) {
        acc[reason] = (acc[reason] || 0) + 1;
      }
      return acc;
    }, {}),
    items,
  };
}

try {
  const args = parseArgs(process.argv);
  if (args.help) {
    console.log(USAGE);
    process.exit(0);
  }
  console.log(JSON.stringify(inspectCorpus(args), null, 2));
} catch (error) {
  console.error(error && error.stack ? error.stack : String(error));
  process.exit(1);
}
