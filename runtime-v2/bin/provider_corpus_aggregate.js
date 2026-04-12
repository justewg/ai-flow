#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { evaluateProviderRolloutGate } = require("../src");

const USAGE = [
  "Usage: provider_corpus_aggregate.js --state-dir <path> [--state-dir <path> ...]",
  "       provider_corpus_aggregate.js --state-dirs <path1,path2,...>",
  "       provider_corpus_aggregate.js --recover-issues-from-telemetry --state-dir <path> [...]",
].join("\n");

function parseArgs(argv) {
  const args = {
    stateDirs: [],
    recoverIssuesFromTelemetry: false,
  };

  for (let index = 2; index < argv.length; index += 1) {
    const token = argv[index];
    const next = argv[index + 1];
    if (token === "--state-dir") {
      if (!next) throw new Error("Missing value for --state-dir");
      args.stateDirs.push(next);
      index += 1;
    } else if (token === "--state-dirs") {
      if (!next) throw new Error("Missing value for --state-dirs");
      args.stateDirs.push(...next.split(",").map((item) => item.trim()).filter(Boolean));
      index += 1;
    } else if (token === "--recover-issues-from-telemetry") {
      args.recoverIssuesFromTelemetry = true;
    } else if (token === "-h" || token === "--help") {
      args.help = true;
    } else {
      throw new Error(`Unknown option: ${token}`);
    }
  }

  if (!args.help && args.stateDirs.length === 0) {
    throw new Error(USAGE);
  }

  return args;
}

function readJson(filePath) {
  if (!fs.existsSync(filePath)) {
    return null;
  }
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function readJsonl(filePath) {
  if (!fs.existsSync(filePath)) {
    return [];
  }
  const raw = fs.readFileSync(filePath, "utf8").trim();
  if (raw === "") {
    return [];
  }
  return raw
    .split(/\n+/)
    .filter(Boolean)
    .map((line) => JSON.parse(line));
}

function emptyTelemetrySummary() {
  return {
    count: 0,
    tokenUsageTotal: 0,
    latencyMsTotal: 0,
    estimatedCostTotal: 0,
    compareSummaryCounts: {},
  };
}

function telemetrySummaryFromRecords(records) {
  const summary = emptyTelemetrySummary();
  for (const record of records || []) {
    summary.count += 1;
    summary.tokenUsageTotal += Number(record.tokenUsage || 0);
    summary.latencyMsTotal += Number(record.latencyMs || 0);
    summary.estimatedCostTotal = Number((summary.estimatedCostTotal + Number(record.estimatedCost || 0)).toFixed(12));
    const compareSummary = record.compareSummary || "none";
    summary.compareSummaryCounts[compareSummary] = (summary.compareSummaryCounts[compareSummary] || 0) + 1;
  }
  return summary;
}

function mergeTelemetrySummary(target, source) {
  const input = source && typeof source === "object" ? source : {};
  target.count += Number(input.count || 0);
  target.tokenUsageTotal += Number(input.tokenUsageTotal || 0);
  target.latencyMsTotal += Number(input.latencyMsTotal || 0);
  target.estimatedCostTotal = Number((target.estimatedCostTotal + Number(input.estimatedCostTotal || 0)).toFixed(12));
  for (const [key, value] of Object.entries(input.compareSummaryCounts || {})) {
    target.compareSummaryCounts[key] = (target.compareSummaryCounts[key] || 0) + Number(value || 0);
  }
  return target;
}

function uniqueStrings(values) {
  return [...new Set(values.filter((value) => typeof value === "string" && value.trim() !== ""))].sort();
}

function issueNumberFromTaskId(taskId) {
  const match = String(taskId || "").match(/^ISSUE-(\d+)$/);
  return match ? match[1] : null;
}

function compareTelemetryRecords(records, moduleName, shadowProvider) {
  return (records || [])
    .filter(
      (record) =>
        record &&
        record.module === moduleName &&
        record.shadowProvider === shadowProvider &&
        (record.compareMode === "dry_run" || record.compareMode === "shadow") &&
        record.primaryProvider === "local",
    )
    .sort((left, right) => String(left.ts || "").localeCompare(String(right.ts || "")));
}

function latestRecordsByTask(records) {
  const byTask = new Map();
  for (const record of records || []) {
    if (typeof record.taskId !== "string" || record.taskId.trim() === "") {
      continue;
    }
    byTask.set(record.taskId, record);
  }
  return [...byTask.values()].sort((left, right) => String(left.taskId).localeCompare(String(right.taskId)));
}

function readBatch(stateDirInput, args) {
  const stateDir = path.resolve(stateDirInput);
  const summary = readJson(path.join(stateDir, "provider_corpus_summary.json"));
  const gate = readJson(path.join(stateDir, "provider_corpus_gate.json")) || summary?.gate || null;
  const moduleName = summary?.module || gate?.module || "intake.interpretation";
  const shadowProvider = summary?.shadowProvider || gate?.shadowProvider || "claude";
  const telemetryRecords = readJsonl(path.join(stateDir, "provider_telemetry.jsonl"));
  const comparableTelemetryRecords = compareTelemetryRecords(telemetryRecords, moduleName, shadowProvider);
  const recoveredGateRecords = latestRecordsByTask(comparableTelemetryRecords);
  const recoveredIssues = uniqueStrings(recoveredGateRecords.map((record) => issueNumberFromTaskId(record.taskId)).filter(Boolean));
  const summaryIssues = Array.isArray(summary?.issues) ? summary.issues.map(String) : [];

  if (!summary) {
    return {
      stateDir,
      ready: false,
      blockingReasons: ["missing_summary"],
      issues: [],
      runIssues: [],
      telemetry: emptyTelemetrySummary(),
      gateTelemetry: emptyTelemetrySummary(),
      recoveredFromTelemetry: false,
    };
  }

  if (args.recoverIssuesFromTelemetry && recoveredGateRecords.length > 0) {
    const recoveredGate = evaluateProviderRolloutGate(recoveredGateRecords, {
      module: moduleName,
      shadowProvider,
      minSamples: recoveredIssues.length,
      providerHealth: gate?.providerHealth || null,
    });
    return {
      stateDir,
      ready: recoveredGate.ready === true,
      blockingReasons: Array.isArray(recoveredGate.blockingReasons) ? recoveredGate.blockingReasons : [],
      issues: recoveredIssues,
      runIssues: Array.isArray(summary.runIssues) ? summary.runIssues.map(String) : [],
      telemetry: telemetrySummaryFromRecords(comparableTelemetryRecords),
      gateTelemetry: telemetrySummaryFromRecords(recoveredGateRecords),
      recoveredFromTelemetry: true,
      originalIssues: summaryIssues,
      originalBlockingReasons: Array.isArray(gate?.blockingReasons) ? gate.blockingReasons : [],
    };
  }

  return {
    stateDir,
    ready: gate?.ready === true,
    blockingReasons: Array.isArray(gate?.blockingReasons) ? gate.blockingReasons : [],
    issues: summaryIssues,
    runIssues: Array.isArray(summary.runIssues) ? summary.runIssues.map(String) : [],
    telemetry: summary.telemetry || emptyTelemetrySummary(),
    gateTelemetry: summary.gateTelemetry || emptyTelemetrySummary(),
    recoveredFromTelemetry: false,
  };
}

function aggregateCorpus(args) {
  const batches = args.stateDirs.map((stateDir) => readBatch(stateDir, args));
  const telemetry = batches.reduce((acc, batch) => mergeTelemetrySummary(acc, batch.telemetry), emptyTelemetrySummary());
  const gateTelemetry = batches.reduce((acc, batch) => mergeTelemetrySummary(acc, batch.gateTelemetry), emptyTelemetrySummary());
  const blockingReasons = batches.flatMap((batch) =>
    batch.blockingReasons.map((reason) => `${path.basename(batch.stateDir)}:${reason}`),
  );

  return {
    ready: batches.every((batch) => batch.ready) && blockingReasons.length === 0,
    blockingReasons,
    batchCount: batches.length,
    issueCount: uniqueStrings(batches.flatMap((batch) => batch.issues)).length,
    issues: uniqueStrings(batches.flatMap((batch) => batch.issues)),
    telemetry,
    gateTelemetry,
    batches,
  };
}

try {
  const args = parseArgs(process.argv);
  if (args.help) {
    console.log(USAGE);
    process.exit(0);
  }
  console.log(JSON.stringify(aggregateCorpus(args), null, 2));
} catch (error) {
  console.error(error && error.stack ? error.stack : String(error));
  process.exit(1);
}
