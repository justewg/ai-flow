#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const { evaluateProviderRolloutGate } = require("../src");

function parseArgs(argv) {
  const args = {
    ledgerFile: "",
    providerHealthFile: "",
    module: "intake.interpretation",
    shadowProvider: "claude",
    minSamples: 5,
  };

  for (let index = 2; index < argv.length; index += 1) {
    const token = argv[index];
    const next = argv[index + 1];
    if (token === "--ledger-file") {
      args.ledgerFile = next;
      index += 1;
    } else if (token === "--provider-health-file") {
      args.providerHealthFile = next;
      index += 1;
    } else if (token === "--module") {
      args.module = next;
      index += 1;
    } else if (token === "--shadow-provider") {
      args.shadowProvider = next;
      index += 1;
    } else if (token === "--min-samples") {
      args.minSamples = Number.parseInt(next, 10);
      index += 1;
    }
  }

  if (!args.ledgerFile) {
    throw new Error(
      "Usage: provider_rollout_gate.js --ledger-file <provider_telemetry.jsonl> [--provider-health-file <claude_provider_health.json>] [--module <module>] [--shadow-provider <provider>] [--min-samples <n>]",
    );
  }

  return args;
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

function readJson(filePath) {
  if (!filePath || !fs.existsSync(filePath)) {
    return null;
  }
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function main() {
  const args = parseArgs(process.argv);
  const records = readJsonl(args.ledgerFile);
  const providerHealth = readJson(args.providerHealthFile);
  const summary = evaluateProviderRolloutGate(records, {
    module: args.module,
    shadowProvider: args.shadowProvider,
    minSamples: args.minSamples,
    providerHealth,
  });
  console.log(JSON.stringify(summary, null, 2));
}

try {
  main();
} catch (error) {
  console.error(error && error.stack ? error.stack : String(error));
  process.exit(1);
}
