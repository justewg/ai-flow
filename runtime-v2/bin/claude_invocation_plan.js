#!/usr/bin/env node
"use strict";

const { buildClaudeInvocationPlan } = require("../src");

function parseArgs(argv) {
  const args = {
    taskRepo: "",
    promptFile: "",
    responseFile: "",
    module: "",
    preferredProvider: "",
    useAutoRouter: false,
    providerConfigJson: process.env.AI_FLOW_PROVIDER_ROUTING_JSON || "{}",
    taskProfile: "",
    reasoningHeavy: false,
    ambiguousHumanText: false,
  };

  for (let index = 2; index < argv.length; index += 1) {
    const token = argv[index];
    const next = argv[index + 1];
    if (token === "--task-repo") {
      args.taskRepo = next;
      index += 1;
    } else if (token === "--prompt-file") {
      args.promptFile = next;
      index += 1;
    } else if (token === "--response-file") {
      args.responseFile = next;
      index += 1;
    } else if (token === "--module") {
      args.module = next;
      index += 1;
    } else if (token === "--preferred-provider") {
      args.preferredProvider = next;
      index += 1;
    } else if (token === "--use-auto-router") {
      args.useAutoRouter = true;
    } else if (token === "--provider-config-json") {
      args.providerConfigJson = next;
      index += 1;
    } else if (token === "--task-profile") {
      args.taskProfile = next;
      index += 1;
    } else if (token === "--reasoning-heavy") {
      args.reasoningHeavy = true;
    } else if (token === "--ambiguous-human-text") {
      args.ambiguousHumanText = true;
    }
  }

  if (!args.promptFile || !args.responseFile || !args.module) {
    throw new Error(
      "Usage: claude_invocation_plan.js --prompt-file <path> --response-file <path> --module <name> [--task-repo <path>] [--preferred-provider <provider>] [--use-auto-router] [--provider-config-json <json>] [--task-profile <profile>] [--reasoning-heavy] [--ambiguous-human-text]",
    );
  }

  return args;
}

function parseConfig(raw) {
  if (!raw || raw.trim() === "") {
    return {};
  }
  return JSON.parse(raw);
}

function main() {
  const args = parseArgs(process.argv);
  const plan = buildClaudeInvocationPlan(
    {
      taskRepo: args.taskRepo || undefined,
      promptFile: args.promptFile,
      responseFile: args.responseFile,
      module: args.module,
      preferredProvider: args.preferredProvider || undefined,
      useAutoRouter: args.useAutoRouter,
      hints: {
        taskProfile: args.taskProfile || undefined,
        reasoningHeavy: args.reasoningHeavy,
        ambiguousHumanText: args.ambiguousHumanText,
      },
    },
    parseConfig(args.providerConfigJson),
  );

  console.log(JSON.stringify(plan, null, 2));
}

try {
  main();
} catch (error) {
  console.error(error && error.stack ? error.stack : String(error));
  process.exit(1);
}
