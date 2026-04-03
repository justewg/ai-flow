#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const {
  buildIntakeInterpretationRequest,
  normalizeIntakeInterpretationResponse,
  buildAskHumanRequest,
  normalizeAskHumanResponse,
} = require("../src");

function readJson(path) {
  return JSON.parse(fs.readFileSync(path, "utf8"));
}

function readText(path) {
  return fs.readFileSync(path, "utf8");
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

function interpretationRequest(args) {
  const source = readJson(args["source-file"]);
  const spec = readJson(args["spec-file"]);
  return buildIntakeInterpretationRequest({
    taskId: source.taskId,
    issueNumber: Number.parseInt(source.issueNumber, 10),
    title: source.title,
    body: source.body,
    replyText: source.replyText,
    candidateTargetFiles: spec.candidateTargetFiles || [],
    repositoryContext: spec.repositoryContext || {},
  });
}

function interpretationResponse(args) {
  const spec = readJson(args["spec-file"]);
  return normalizeIntakeInterpretationResponse({
    decision: spec.profileDecision,
    decisionReason: spec.decisionReason,
    interpretedIntent: spec.interpretedIntent,
    confidence: spec.confidence || {},
    candidateTargetFiles: spec.candidateTargetFiles || [],
    rationale: spec.rationale || [],
    askHumanQuestion: spec.profileDecision === "human_needed" ? "Нужна более точная привязка задачи к компоненту или файлу." : null,
  });
}

function askRequest(args) {
  return buildAskHumanRequest({
    taskId: args["task-id"],
    issueNumber: Number.parseInt(args["issue-number"], 10),
    kind: args.kind,
    contextLine: args["context-line"] || "",
    executorRemark: args["executor-remark-file"] ? readText(args["executor-remark-file"]) : "",
    messageText: readText(args["message-file"]),
  });
}

function askResponse(args) {
  const kind = args.kind;
  const body = readText(args["message-file"]);
  const recommendedAction = args["recommended-action"] || (kind === "BLOCKER" ? "clarify" : "continue");
  const options = args["options-file"] ? readText(args["options-file"]).split(/\r?\n/).map((line) => line.trim()).filter(Boolean) : [];
  return normalizeAskHumanResponse({
    kind,
    body,
    expectsReply: true,
    recommendedAction,
    options,
  });
}

function main() {
  const { command, args } = parseArgs(process.argv);
  let result;
  switch (command) {
    case "interpretation-request":
      result = interpretationRequest(args);
      break;
    case "interpretation-response":
      result = interpretationResponse(args);
      break;
    case "ask-request":
      result = askRequest(args);
      break;
    case "ask-response":
      result = askResponse(args);
      break;
    default:
      throw new Error(
        "Usage: intake_contract_artifact.js <interpretation-request|interpretation-response|ask-request|ask-response> ...",
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
