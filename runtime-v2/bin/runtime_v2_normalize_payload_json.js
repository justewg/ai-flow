#!/usr/bin/env node
"use strict";

function parseArgs(argv) {
  const args = {
    payloadJson: "{}",
  };

  for (let index = 2; index < argv.length; index += 1) {
    const token = argv[index];
    const next = argv[index + 1];
    if (token === "--payload-json") {
      args.payloadJson = next;
      index += 1;
    }
  }

  return args;
}

function extractLeadingJson(source) {
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

function normalizePayloadJson(raw) {
  const source = String(raw || "{}");

  try {
    return JSON.stringify(JSON.parse(source));
  } catch (_primaryError) {
    const extracted = extractLeadingJson(source);
    if (!extracted) {
      return "{}";
    }

    try {
      return JSON.stringify(JSON.parse(extracted));
    } catch (_secondaryError) {
      return "{}";
    }
  }
}

function main() {
  const args = parseArgs(process.argv);
  process.stdout.write(normalizePayloadJson(args.payloadJson));
}

main();
