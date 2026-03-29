#!/usr/bin/env node
"use strict";

const path = require("path");

const {
  createAiFlowV2StateStore,
  createFileAdapter,
  applyLegacyEventBridge,
} = require("../src");

function parseArgs(argv) {
  const args = {
    legacyStateDir: "",
    storeDir: "",
    repo: "",
    taskId: "",
    issueNumber: "",
    eventType: "",
    eventId: "",
    source: "runtime_v2_event_bridge",
    dedupKey: "",
    payloadJson: "{}",
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
    } else if (token === "--event-type") {
      args.eventType = next;
      index += 1;
    } else if (token === "--event-id") {
      args.eventId = next;
      index += 1;
    } else if (token === "--source") {
      args.source = next;
      index += 1;
    } else if (token === "--dedup-key") {
      args.dedupKey = next;
      index += 1;
    } else if (token === "--payload-json") {
      args.payloadJson = next;
      index += 1;
    }
  }

  if (!args.legacyStateDir || !args.storeDir || !args.repo || !args.taskId || !args.eventType) {
    throw new Error(
      "Usage: runtime_v2_apply_event.js --legacy-state-dir <dir> --store-dir <dir> --repo <owner/repo> --task-id <id> --event-type <type> [--issue-number <n>] [--event-id <id>] [--dedup-key <key>] [--payload-json <json>]",
    );
  }
  return args;
}

function extractLeadingJson(raw) {
  const source = String(raw || "");
  let index = 0;
  while (index < source.length && /\s/.test(source[index])) {
    index += 1;
  }
  if (index >= source.length || (source[index] !== "{" && source[index] !== "[")) {
    return null;
  }

  const opening = source[index];
  const closing = opening === "{" ? "}" : "]";
  let depth = 0;
  let inString = false;
  let escaped = false;

  for (let cursor = index; cursor < source.length; cursor += 1) {
    const char = source[cursor];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (char === "\\") {
        escaped = true;
      } else if (char === "\"") {
        inString = false;
      }
      continue;
    }

    if (char === "\"") {
      inString = true;
      continue;
    }
    if (char === opening) {
      depth += 1;
      continue;
    }
    if (char === closing) {
      depth -= 1;
      if (depth === 0) {
        return source.slice(index, cursor + 1);
      }
    }
  }

  return null;
}

function parsePayloadJson(raw) {
  const payloadText = String(raw || "{}");
  try {
    return { payload: JSON.parse(payloadText), normalized: payloadText, warning: null };
  } catch (primaryError) {
    const extracted = extractLeadingJson(payloadText);
    if (extracted) {
      try {
        return {
          payload: JSON.parse(extracted),
          normalized: extracted,
          warning: `payload_json_trimmed_after_parse_error:${primaryError.message}`,
        };
      } catch (_secondaryError) {
        // Fall through to empty payload.
      }
    }
    return {
      payload: {},
      normalized: "{}",
      warning: `payload_json_invalid_fallback_empty:${primaryError.message}`,
    };
  }
}

async function main() {
  const args = parseArgs(process.argv);
  const parsedPayload = parsePayloadJson(args.payloadJson);
  const store = createAiFlowV2StateStore({
    adapter: createFileAdapter({ storeDir: path.resolve(args.storeDir) }),
  });
  await store.init();

  const result = await applyLegacyEventBridge(store, {
    legacyStateDir: path.resolve(args.legacyStateDir),
    repo: args.repo,
    taskId: args.taskId,
    issueNumber: args.issueNumber,
    eventType: args.eventType,
    eventId: args.eventId,
    source: args.source,
    dedupKey: args.dedupKey,
    payload: parsedPayload.payload,
  });
  const output = {
    ...result,
  };
  if (parsedPayload.warning) {
    output.payloadWarning = parsedPayload.warning;
    output.payloadJsonNormalized = parsedPayload.normalized;
  }
  console.log(JSON.stringify(output, null, 2));
}

main().catch((error) => {
  console.error(error && error.stack ? error.stack : String(error));
  process.exit(1);
});
