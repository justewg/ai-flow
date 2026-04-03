#!/usr/bin/env node
"use strict";

const { buildCodexInvocationPlan } = require("../src");

function parseArgs(argv) {
  const args = {
    taskRepo: "",
    responseFile: "",
    module: "",
    dangerouslyBypassSandbox: false,
    preferredProvider: "",
    useAutoRouter: false,
    providerConfigJson: process.env.AI_FLOW_PROVIDER_ROUTING_JSON || "{}",
  };

  for (let index = 2; index < argv.length; index += 1) {
    const token = argv[index];
    const next = argv[index + 1];
    if (token === "--task-repo") {
      args.taskRepo = next;
      index += 1;
    } else if (token === "--response-file") {
      args.responseFile = next;
      index += 1;
    } else if (token === "--module") {
      args.module = next;
      index += 1;
    } else if (token === "--dangerously-bypass-sandbox") {
      args.dangerouslyBypassSandbox = true;
    } else if (token === "--preferred-provider") {
      args.preferredProvider = next;
      index += 1;
    } else if (token === "--use-auto-router") {
      args.useAutoRouter = true;
    } else if (token === "--provider-config-json") {
      args.providerConfigJson = next;
      index += 1;
    }
  }

  if (!args.taskRepo || !args.responseFile || !args.module) {
    throw new Error(
      "Usage: codex_invocation_plan.js --task-repo <path> --response-file <path> --module <name> [--dangerously-bypass-sandbox] [--preferred-provider <provider>] [--use-auto-router] [--provider-config-json <json>]",
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
  const plan = buildCodexInvocationPlan(
    {
      taskRepo: args.taskRepo,
      responseFile: args.responseFile,
      module: args.module,
      dangerouslyBypassSandbox: args.dangerouslyBypassSandbox,
      preferredProvider: args.preferredProvider || undefined,
      useAutoRouter: args.useAutoRouter,
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
