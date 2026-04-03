#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const { compareInterpretationResults, compareAskHumanResults } = require("../src");

function readJson(path) {
  return JSON.parse(fs.readFileSync(path, "utf8"));
}

function parseArgs(argv) {
  const command = argv[2] || "";
  const args = {};
  for (let index = 3; index < argv.length; index += 1) {
    const token = argv[index];
    const next = argv[index + 1];
    if (token.startsWith("--")) {
      const key = token.slice(2);
      if (next && !next.startsWith("--")) {
        args[key] = next;
        index += 1;
      } else {
        args[key] = "1";
      }
    }
  }
  return { command, args };
}

function commonOptions(args) {
  return {
    compareMode: args["compare-mode"] || "disabled",
    primaryProvider: args["primary-provider"] || "local",
    shadowProvider: args["shadow-provider"] || "claude",
    publishDecision: false,
  };
}

function main() {
  const { command, args } = parseArgs(process.argv);
  const primary = readJson(args["primary-file"]);
  const shadow = readJson(args["shadow-file"]);
  let result;

  switch (command) {
    case "interpretation":
      result = compareInterpretationResults(primary, shadow, commonOptions(args));
      break;
    case "ask-human":
      result = compareAskHumanResults(primary, shadow, commonOptions(args));
      break;
    default:
      throw new Error(
        "Usage: intake_compare_artifact.js <interpretation|ask-human> --primary-file <path> --shadow-file <path> [--compare-mode <mode>] [--primary-provider <provider>] [--shadow-provider <provider>]",
      );
  }

  console.log(JSON.stringify(result, null, 2));
}

try {
  main();
} catch (error) {
  console.error(error && error.stack ? error.stack : String(error));
  process.exit(1);
}
