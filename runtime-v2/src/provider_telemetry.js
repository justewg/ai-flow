"use strict";

const { ValidationError } = require("./errors");
const { PROVIDERS, MODULES, OUTCOMES } = require("./provider_contract");

function assertNonEmptyString(value, fieldName) {
  if (typeof value !== "string" || value.trim() === "") {
    throw new ValidationError(`${fieldName} must be a non-empty string`, { fieldName });
  }
  return value.trim();
}

function assertEnum(value, allowedSet, fieldName) {
  const normalized = assertNonEmptyString(value, fieldName);
  if (!allowedSet.has(normalized)) {
    throw new ValidationError(`${fieldName} has unsupported value: ${normalized}`, { fieldName, value: normalized });
  }
  return normalized;
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

function optionalNumber(value, fieldName) {
  if (value === undefined || value === null || value === "") {
    return null;
  }
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0) {
    throw new ValidationError(`${fieldName} must be a non-negative finite number`, { fieldName });
  }
  return value;
}

function optionalFiniteNumber(value, fieldName) {
  if (value === undefined || value === null || value === "") {
    return null;
  }
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new ValidationError(`${fieldName} must be a finite number`, { fieldName });
  }
  return value;
}

function optionalBoolean(value) {
  if (value === undefined || value === null || value === "") {
    return null;
  }
  return value === true;
}

function normalizeProviderTelemetryRecord(input) {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw new ValidationError("provider telemetry record must be an object");
  }

  return {
    ts: assertNonEmptyString(input.ts, "ts"),
    requestId: assertNonEmptyString(input.requestId, "requestId"),
    taskId: assertNonEmptyString(input.taskId, "taskId"),
    module: assertEnum(input.module, MODULES, "module"),
    requestedProvider: assertEnum(input.requestedProvider || "auto", PROVIDERS, "requestedProvider"),
    effectiveProvider: assertEnum(input.effectiveProvider, PROVIDERS, "effectiveProvider"),
    outcome: assertEnum(input.outcome, OUTCOMES, "outcome"),
    fallbackUsed: input.fallbackUsed === true,
    fallbackFromProvider: optionalString(input.fallbackFromProvider),
    decisionReason: optionalString(input.decisionReason),
    timeoutMs: optionalInteger(input.timeoutMs, "timeoutMs"),
    budgetKey: optionalString(input.budgetKey),
    errorClass: optionalString(input.errorClass),
    errorMessage: optionalString(input.errorMessage),
    latencyMs: optionalInteger(input.latencyMs, "latencyMs"),
    tokenUsage: optionalInteger(input.tokenUsage, "tokenUsage"),
    estimatedCost: optionalNumber(input.estimatedCost, "estimatedCost"),
    misroute: input.misroute === true,
    compareMode: optionalString(input.compareMode),
    primaryProvider: optionalString(input.primaryProvider),
    shadowProvider: optionalString(input.shadowProvider),
    schemaValidPrimary: optionalBoolean(input.schemaValidPrimary),
    schemaValidShadow: optionalBoolean(input.schemaValidShadow),
    profileMatch: optionalBoolean(input.profileMatch),
    targetFilesMatch: optionalBoolean(input.targetFilesMatch),
    humanNeededMatch: optionalBoolean(input.humanNeededMatch),
    confidenceDelta: optionalFiniteNumber(input.confidenceDelta, "confidenceDelta"),
    compareSummary: optionalString(input.compareSummary),
    publishDecision: optionalBoolean(input.publishDecision),
  };
}

function summarizeProviderTelemetry(records) {
  const summary = {
    total: 0,
    byProvider: {},
    byModule: {},
    byOutcome: {},
    fallbackCount: 0,
    misrouteCount: 0,
    decisionReasonCounts: {},
    errorClassCounts: {},
    compareModeCounts: {},
    compareSummaryCounts: {},
  };

  for (const raw of records || []) {
    const record = normalizeProviderTelemetryRecord(raw);
    summary.total += 1;
    summary.byProvider[record.effectiveProvider] = (summary.byProvider[record.effectiveProvider] || 0) + 1;
    summary.byModule[record.module] = (summary.byModule[record.module] || 0) + 1;
    summary.byOutcome[record.outcome] = (summary.byOutcome[record.outcome] || 0) + 1;
    if (record.fallbackUsed) {
      summary.fallbackCount += 1;
    }
    if (record.misroute) {
      summary.misrouteCount += 1;
    }
    if (record.decisionReason) {
      summary.decisionReasonCounts[record.decisionReason] = (summary.decisionReasonCounts[record.decisionReason] || 0) + 1;
    }
    if (record.errorClass) {
      summary.errorClassCounts[record.errorClass] = (summary.errorClassCounts[record.errorClass] || 0) + 1;
    }
    if (record.compareMode) {
      summary.compareModeCounts[record.compareMode] = (summary.compareModeCounts[record.compareMode] || 0) + 1;
    }
    if (record.compareSummary) {
      summary.compareSummaryCounts[record.compareSummary] = (summary.compareSummaryCounts[record.compareSummary] || 0) + 1;
    }
  }

  return summary;
}

module.exports = {
  normalizeProviderTelemetryRecord,
  summarizeProviderTelemetry,
};
