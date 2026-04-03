#!/usr/bin/env node
"use strict";

const { resolveProviderRoute } = require("../src");

function parseArgs(argv) {
  const args = {
    module: "",
    taskId: "",
    issueNumber: null,
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
    if (token === "--module") {
      args.module = next;
      index += 1;
    } else if (token === "--task-id") {
      args.taskId = next;
      index += 1;
    } else if (token === "--issue-number") {
      args.issueNumber = Number.parseInt(next, 10);
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

  if (!args.module || !args.taskId) {
    throw new Error(
      "Usage: provider_route.js --module <name> --task-id <task-id> [--issue-number <n>] [--preferred-provider <provider>] [--use-auto-router] [--provider-config-json <json>] [--task-profile <profile>] [--reasoning-heavy] [--ambiguous-human-text]",
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
  const route = resolveProviderRoute(
    {
      module: args.module,
      taskId: args.taskId,
      issueNumber: Number.isInteger(args.issueNumber) ? args.issueNumber : undefined,
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

  console.log(JSON.stringify(route, null, 2));
}

try {
  main();
} catch (error) {
  console.error(error && error.stack ? error.stack : String(error));
  process.exit(1);
}
