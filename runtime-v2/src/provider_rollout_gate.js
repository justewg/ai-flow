"use strict";

const { normalizeProviderTelemetryRecord } = require("./provider_telemetry");
const { ValidationError } = require("./errors");

function optionalPositiveInteger(value, fieldName, defaultValue) {
  if (value === undefined || value === null || value === "") {
    return defaultValue;
  }
  if (!Number.isInteger(value) || value <= 0) {
    throw new ValidationError(`${fieldName} must be a positive integer`, { fieldName });
  }
  return value;
}

function optionalNumberInRange(value, fieldName, defaultValue) {
  if (value === undefined || value === null || value === "") {
    return defaultValue;
  }
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0 || value > 1) {
    throw new ValidationError(`${fieldName} must be a finite number between 0 and 1`, { fieldName });
  }
  return value;
}

function normalizeGateOptions(input = {}) {
  const options = input && typeof input === "object" && !Array.isArray(input) ? input : {};
  const rawProviderHealth =
    options.providerHealth && typeof options.providerHealth === "object" && !Array.isArray(options.providerHealth)
      ? options.providerHealth
      : null;
  return {
    module: typeof options.module === "string" && options.module.trim() !== "" ? options.module.trim() : "intake.interpretation",
    shadowProvider:
      typeof options.shadowProvider === "string" && options.shadowProvider.trim() !== ""
        ? options.shadowProvider.trim()
        : "claude",
    minSamples: optionalPositiveInteger(options.minSamples, "minSamples", 5),
    maxSchemaInvalidCount:
      options.maxSchemaInvalidCount === undefined || options.maxSchemaInvalidCount === null || options.maxSchemaInvalidCount === ""
        ? 0
        : optionalPositiveInteger(options.maxSchemaInvalidCount, "maxSchemaInvalidCount", 1),
    maxErrorCount:
      options.maxErrorCount === undefined || options.maxErrorCount === null || options.maxErrorCount === ""
        ? 0
        : optionalPositiveInteger(options.maxErrorCount, "maxErrorCount", 1),
    maxProfileMismatchRate: optionalNumberInRange(options.maxProfileMismatchRate, "maxProfileMismatchRate", 0.2),
    maxTargetFilesMismatchRate: optionalNumberInRange(options.maxTargetFilesMismatchRate, "maxTargetFilesMismatchRate", 0.2),
    maxHumanNeededMismatchRate: optionalNumberInRange(options.maxHumanNeededMismatchRate, "maxHumanNeededMismatchRate", 0.1),
    providerHealth:
      rawProviderHealth === null
        ? null
        : {
            status:
              typeof rawProviderHealth.status === "string" && rawProviderHealth.status.trim() !== ""
                ? rawProviderHealth.status.trim()
                : typeof rawProviderHealth.lastStatus === "string"
                  ? rawProviderHealth.lastStatus.trim()
                  : "",
            lastErrorClass:
              typeof rawProviderHealth.lastErrorClass === "string" ? rawProviderHealth.lastErrorClass.trim() : "",
            lastErrorMessage:
              typeof rawProviderHealth.lastErrorMessage === "string" ? rawProviderHealth.lastErrorMessage : "",
            cooldownSec: Number.isInteger(rawProviderHealth.cooldownSec) ? rawProviderHealth.cooldownSec : 0,
            lastFailureAt:
              typeof rawProviderHealth.lastFailureAt === "string" ? rawProviderHealth.lastFailureAt.trim() : "",
          },
  };
}

function countWhere(records, predicate) {
  return records.reduce((total, record) => total + (predicate(record) ? 1 : 0), 0);
}

function ratio(count, total) {
  return total > 0 ? Number((count / total).toFixed(6)) : null;
}

function compareRecordsForModule(records, options) {
  return (records || [])
    .map(normalizeProviderTelemetryRecord)
    .filter(
      (record) =>
        record.module === options.module &&
        record.compareMode !== null &&
        (record.compareMode === "dry_run" || record.compareMode === "shadow") &&
        record.primaryProvider === "local" &&
        record.shadowProvider === options.shadowProvider,
    )
    .sort((left, right) => String(left.ts).localeCompare(String(right.ts)));
}

function evaluateProviderRolloutGate(records, input = {}) {
  const options = normalizeGateOptions(input);
  const compareRecords = compareRecordsForModule(records, options);
  const recentRecords = compareRecords.slice(-options.minSamples);
  const sampleSize = recentRecords.length;

  const schemaInvalidCount = countWhere(recentRecords, (record) => record.schemaValidShadow === false);
  const errorCount = countWhere(recentRecords, (record) => record.outcome !== "success");
  const profileMismatchCount = countWhere(recentRecords, (record) => record.profileMatch === false);
  const targetFilesMismatchCount = countWhere(recentRecords, (record) => record.targetFilesMatch === false);
  const unsafeTargetFilesMismatchCount = countWhere(
    recentRecords,
    (record) => record.targetFilesMatch === false && record.targetFilesDriftTolerated !== true,
  );
  const humanNeededMismatchCount = countWhere(recentRecords, (record) => record.humanNeededMatch === false);

  const profileMismatchRate = ratio(profileMismatchCount, sampleSize);
  const targetFilesMismatchRate = ratio(targetFilesMismatchCount, sampleSize);
  const unsafeTargetFilesMismatchRate = ratio(unsafeTargetFilesMismatchCount, sampleSize);
  const humanNeededMismatchRate = ratio(humanNeededMismatchCount, sampleSize);

  const blockingReasons = [];
  if (sampleSize < options.minSamples) {
    blockingReasons.push(`insufficient_samples:${sampleSize}/${options.minSamples}`);
  }
  if (schemaInvalidCount > options.maxSchemaInvalidCount) {
    blockingReasons.push(`schema_invalid:${schemaInvalidCount}`);
  }
  if (errorCount > options.maxErrorCount) {
    blockingReasons.push(`shadow_errors:${errorCount}`);
  }
  if (profileMismatchRate !== null && profileMismatchRate > options.maxProfileMismatchRate) {
    blockingReasons.push(`profile_mismatch_rate:${profileMismatchRate}`);
  }
  if (unsafeTargetFilesMismatchRate !== null && unsafeTargetFilesMismatchRate > options.maxTargetFilesMismatchRate) {
    blockingReasons.push(`unsafe_target_files_mismatch_rate:${unsafeTargetFilesMismatchRate}`);
  }
  if (humanNeededMismatchRate !== null && humanNeededMismatchRate > options.maxHumanNeededMismatchRate) {
    blockingReasons.push(`human_needed_mismatch_rate:${humanNeededMismatchRate}`);
  }
  if (
    options.providerHealth &&
    options.providerHealth.status === "auth_error" &&
    (options.providerHealth.lastErrorClass === "auth_missing" || options.providerHealth.lastErrorClass === "auth_forbidden")
  ) {
    blockingReasons.push(`provider_unhealthy:${options.providerHealth.lastErrorClass}`);
  }

  return {
    module: options.module,
    shadowProvider: options.shadowProvider,
    ready: blockingReasons.length === 0,
    compareRecordCount: compareRecords.length,
    sampleSize,
    minSamplesRequired: options.minSamples,
    schemaInvalidCount,
    errorCount,
    profileMismatchCount,
    targetFilesMismatchCount,
    unsafeTargetFilesMismatchCount,
    humanNeededMismatchCount,
    profileMismatchRate,
    targetFilesMismatchRate,
    unsafeTargetFilesMismatchRate,
    humanNeededMismatchRate,
    providerHealth: options.providerHealth,
    blockingReasons,
    lastRecords: recentRecords.map((record) => ({
      ts: record.ts,
      taskId: record.taskId,
      issueNumber: record.issueNumber,
      outcome: record.outcome,
      compareSummary: record.compareSummary,
      schemaValidShadow: record.schemaValidShadow,
      profileMatch: record.profileMatch,
      targetFilesMatch: record.targetFilesMatch,
      targetFilesDriftKind: record.targetFilesDriftKind,
      targetFilesDriftTolerated: record.targetFilesDriftTolerated,
      humanNeededMatch: record.humanNeededMatch,
    })),
  };
}

module.exports = {
  normalizeGateOptions,
  evaluateProviderRolloutGate,
};
