#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");

const USAGE = [
  "Usage: provider_corpus_aggregate.js --state-dir <path> [--state-dir <path> ...]",
  "       provider_corpus_aggregate.js --state-dirs <path1,path2,...>",
].join("\n");

function parseArgs(argv) {
  const args = {
    stateDirs: [],
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

function emptyTelemetrySummary() {
  return {
    count: 0,
    tokenUsageTotal: 0,
    latencyMsTotal: 0,
    estimatedCostTotal: 0,
    compareSummaryCounts: {},
  };
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

function readBatch(stateDirInput) {
  const stateDir = path.resolve(stateDirInput);
  const summary = readJson(path.join(stateDir, "provider_corpus_summary.json"));
  const gate = readJson(path.join(stateDir, "provider_corpus_gate.json")) || summary?.gate || null;
  if (!summary) {
    return {
      stateDir,
      ready: false,
      blockingReasons: ["missing_summary"],
      issues: [],
      runIssues: [],
      telemetry: emptyTelemetrySummary(),
      gateTelemetry: emptyTelemetrySummary(),
    };
  }

  return {
    stateDir,
    ready: gate?.ready === true,
    blockingReasons: Array.isArray(gate?.blockingReasons) ? gate.blockingReasons : [],
    issues: Array.isArray(summary.issues) ? summary.issues.map(String) : [],
    runIssues: Array.isArray(summary.runIssues) ? summary.runIssues.map(String) : [],
    telemetry: summary.telemetry || emptyTelemetrySummary(),
    gateTelemetry: summary.gateTelemetry || emptyTelemetrySummary(),
  };
}

function aggregateCorpus(args) {
  const batches = args.stateDirs.map(readBatch);
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
