"use strict";

const { ValidationError } = require("./errors");

const INTERPRETATION_DECISIONS = new Set(["micro", "standard", "human_needed", "blocked"]);
const ASK_HUMAN_KINDS = new Set(["QUESTION", "BLOCKER"]);

function assertNonEmptyString(value, fieldName) {
  if (typeof value !== "string" || value.trim() === "") {
    throw new ValidationError(`${fieldName} must be a non-empty string`, { fieldName });
  }
  return value.trim();
}

function optionalString(value) {
  if (value === undefined || value === null || value === "") {
    return null;
  }
  if (typeof value !== "string") {
    throw new ValidationError("optional string field must be a string");
  }
  return value;
}

function optionalInteger(value, fieldName) {
  if (value === undefined || value === null || value === "") {
    return null;
  }
  if (!Number.isInteger(value) || value < 0) {
    throw new ValidationError(`${fieldName} must be a non-negative integer`, { fieldName });
  }
  return value;
}

function optionalObject(value, fieldName) {
  if (value === undefined || value === null) {
    return {};
  }
  if (typeof value !== "object" || Array.isArray(value)) {
    throw new ValidationError(`${fieldName} must be an object`, { fieldName });
  }
  return value;
}

function optionalArrayOfStrings(value, fieldName) {
  if (value === undefined || value === null) {
    return [];
  }
  if (!Array.isArray(value)) {
    throw new ValidationError(`${fieldName} must be an array`, { fieldName });
  }
  return value
    .filter((item) => typeof item === "string")
    .map((item) => item.trim())
    .filter(Boolean);
}

function assertEnum(value, allowedSet, fieldName) {
  const normalized = assertNonEmptyString(value, fieldName);
  if (!allowedSet.has(normalized)) {
    throw new ValidationError(`${fieldName} has unsupported value: ${normalized}`, { fieldName });
  }
  return normalized;
}

function buildIntakeInterpretationRequest(input) {
  const payload = optionalObject(input, "intakeInterpretationRequest");
  const taskId = assertNonEmptyString(payload.taskId, "taskId");
  const title = assertNonEmptyString(payload.title, "title");
  const issueNumber = optionalInteger(payload.issueNumber, "issueNumber");
  const body = optionalString(payload.body) || "";
  const replyText = optionalString(payload.replyText) || "";
  const candidateTargetFiles = optionalArrayOfStrings(payload.candidateTargetFiles, "candidateTargetFiles");
  const repositoryContext = optionalObject(payload.repositoryContext, "repositoryContext");
  const repositoryHints = optionalArrayOfStrings(repositoryContext.repoHints, "repositoryContext.repoHints");

  const promptSections = [
    `Task ID: ${taskId}`,
    issueNumber !== null ? `Issue: #${issueNumber}` : null,
    `Title: ${title}`,
    body ? `Body:\n${body}` : "Body: <empty>",
    replyText ? `Reply:\n${replyText}` : "Reply: <empty>",
    candidateTargetFiles.length > 0
      ? `Candidate target files:\n- ${candidateTargetFiles.join("\n- ")}`
      : "Candidate target files:\n- none",
    repositoryHints.length > 0
      ? `Repository hints:\n- ${repositoryHints.join("\n- ")}`
      : null,
    Object.keys(repositoryContext).length > 0 ? `Repository context:\n${JSON.stringify(repositoryContext, null, 2)}` : null,
    [
      "Return JSON only with fields:",
      "- decision: micro|standard|human_needed|blocked",
      "- decisionReason: string",
      "- interpretedIntent: string",
      "- confidence: { label, score }",
      "- candidateTargetFiles: string[]",
      "- rationale: string[]",
      "- askHumanQuestion: string|null",
    ].join("\n"),
  ].filter(Boolean);

  return {
    module: "intake.interpretation",
    input: {
      taskId,
      issueNumber,
      title,
      body,
      replyText,
      candidateTargetFiles,
      repositoryHints,
      repositoryContext,
    },
    promptText: promptSections.join("\n\n"),
  };
}

function normalizeIntakeInterpretationResponse(input) {
  const payload = optionalObject(input, "intakeInterpretationResponse");
  const confidence = optionalObject(payload.confidence, "confidence");
  return {
    decision: assertEnum(payload.decision, INTERPRETATION_DECISIONS, "decision"),
    decisionReason: assertNonEmptyString(payload.decisionReason, "decisionReason"),
    interpretedIntent: assertNonEmptyString(payload.interpretedIntent, "interpretedIntent"),
    confidence: {
      label: assertNonEmptyString(confidence.label || "medium", "confidence.label"),
      score: typeof confidence.score === "number" ? confidence.score : Number(confidence.score || 0),
    },
    candidateTargetFiles: optionalArrayOfStrings(payload.candidateTargetFiles, "candidateTargetFiles"),
    rationale: optionalArrayOfStrings(payload.rationale, "rationale"),
    askHumanQuestion: optionalString(payload.askHumanQuestion),
  };
}

function buildAskHumanRequest(input) {
  const payload = optionalObject(input, "askHumanRequest");
  const taskId = assertNonEmptyString(payload.taskId, "taskId");
  const messageText = assertNonEmptyString(payload.messageText, "messageText");
  const kind = assertEnum(payload.kind, ASK_HUMAN_KINDS, "kind");
  const issueNumber = optionalInteger(payload.issueNumber, "issueNumber");
  const contextLine = optionalString(payload.contextLine);
  const executorRemark = optionalString(payload.executorRemark);

  const promptSections = [
    `Task ID: ${taskId}`,
    issueNumber !== null ? `Issue: #${issueNumber}` : null,
    `Kind: ${kind}`,
    contextLine ? `Context: ${contextLine}` : null,
    executorRemark ? `Executor remark:\n${executorRemark}` : null,
    `Raw message:\n${messageText}`,
    [
      "Return JSON only with fields:",
      "- kind: QUESTION|BLOCKER",
      "- body: string",
      "- expectsReply: true",
      "- recommendedAction: continue|clarify|finalize",
      "- options: string[]",
    ].join("\n"),
  ].filter(Boolean);

  return {
    module: "intake.ask_human",
    input: {
      taskId,
      issueNumber,
      kind,
      contextLine,
      executorRemark,
      messageText,
    },
    promptText: promptSections.join("\n\n"),
  };
}

function normalizeAskHumanResponse(input) {
  const payload = optionalObject(input, "askHumanResponse");
  const options = optionalArrayOfStrings(payload.options, "options");
  const recommendedAction = assertNonEmptyString(payload.recommendedAction, "recommendedAction");
  if (!["continue", "clarify", "finalize"].includes(recommendedAction)) {
    throw new ValidationError(`recommendedAction has unsupported value: ${recommendedAction}`, {
      fieldName: "recommendedAction",
    });
  }
  return {
    kind: assertEnum(payload.kind, ASK_HUMAN_KINDS, "kind"),
    body: assertNonEmptyString(payload.body, "body"),
    expectsReply: payload.expectsReply !== false,
    recommendedAction,
    options,
  };
}

module.exports = {
  buildIntakeInterpretationRequest,
  normalizeIntakeInterpretationResponse,
  buildAskHumanRequest,
  normalizeAskHumanResponse,
};
