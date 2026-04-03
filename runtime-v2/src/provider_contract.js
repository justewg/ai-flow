"use strict";

const { ValidationError } = require("./errors");

const PROVIDERS = new Set(["codex", "claude", "local", "auto"]);
const MODULES = new Set([
  "intake.interpretation",
  "intake.ask_human",
  "planning.spec_enrichment",
  "review.summary",
  "execution.micro",
  "execution.standard",
]);
const OUTCOMES = new Set(["success", "error", "fallback"]);

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

function optionalObject(value, fieldName) {
  if (value === undefined || value === null) {
    return {};
  }
  if (typeof value !== "object" || Array.isArray(value)) {
    throw new ValidationError(`${fieldName} must be an object`, { fieldName });
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

function optionalNumber(value, fieldName) {
  if (value === undefined || value === null || value === "") {
    return null;
  }
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0) {
    throw new ValidationError(`${fieldName} must be a non-negative finite number`, { fieldName });
  }
  return value;
}

function assertEnum(value, allowedSet, fieldName) {
  const normalized = assertNonEmptyString(value, fieldName);
  if (!allowedSet.has(normalized)) {
    throw new ValidationError(`${fieldName} has unsupported value: ${normalized}`, { fieldName, value: normalized });
  }
  return normalized;
}

function normalizeProviderRequest(input) {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw new ValidationError("provider request must be an object");
  }

  return {
    requestId: assertNonEmptyString(input.requestId, "requestId"),
    taskId: assertNonEmptyString(input.taskId, "taskId"),
    issueNumber: optionalInteger(input.issueNumber, "issueNumber"),
    module: assertEnum(input.module, MODULES, "module"),
    preferredProvider: assertEnum(input.preferredProvider || "auto", PROVIDERS, "preferredProvider"),
    prompt: assertNonEmptyString(input.prompt, "prompt"),
    input: optionalObject(input.input, "input"),
    meta: optionalObject(input.meta, "meta"),
  };
}

function normalizeProviderResult(input) {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw new ValidationError("provider result must be an object");
  }

  const outcome = assertEnum(input.outcome, OUTCOMES, "outcome");
  const provider = assertEnum(input.provider, PROVIDERS, "provider");

  return {
    requestId: assertNonEmptyString(input.requestId, "requestId"),
    taskId: assertNonEmptyString(input.taskId, "taskId"),
    module: assertEnum(input.module, MODULES, "module"),
    provider,
    outcome,
    outputText: optionalString(input.outputText),
    structuredOutput: optionalObject(input.structuredOutput, "structuredOutput"),
    errorClass: optionalString(input.errorClass),
    errorMessage: optionalString(input.errorMessage),
    latencyMs: optionalInteger(input.latencyMs, "latencyMs"),
    tokenUsage: optionalInteger(input.tokenUsage, "tokenUsage"),
    estimatedCost: optionalNumber(input.estimatedCost, "estimatedCost"),
    fallbackFromProvider: optionalString(input.fallbackFromProvider),
    meta: optionalObject(input.meta, "meta"),
  };
}

module.exports = {
  PROVIDERS,
  MODULES,
  OUTCOMES,
  normalizeProviderRequest,
  normalizeProviderResult,
};
