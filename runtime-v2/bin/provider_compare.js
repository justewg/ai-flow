#!/usr/bin/env node
"use strict";

const { normalizeProviderCompareConfig, resolveProviderCompareMode } = require("../src");

function parseArgs(argv) {
  const args = {
    module: "",
    providerConfigJson: process.env.AI_FLOW_PROVIDER_ROUTING_JSON || "{}",
  };

  for (let index = 2; index < argv.length; index += 1) {
    const token = argv[index];
    const next = argv[index + 1];
    if (token === "--module") {
      args.module = next;
      index += 1;
    } else if (token === "--provider-config-json") {
      args.providerConfigJson = next;
      index += 1;
    }
  }

  if (!args.module) {
    throw new Error("Usage: provider_compare.js --module <module> [--provider-config-json <json>]");
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
  const verdict = resolveProviderCompareMode({ module: args.module }, parseConfig(args.providerConfigJson));
  console.log(JSON.stringify(verdict, null, 2));
}

try {
  main();
} catch (error) {
  console.error(error && error.stack ? error.stack : String(error));
  process.exit(1);
}
