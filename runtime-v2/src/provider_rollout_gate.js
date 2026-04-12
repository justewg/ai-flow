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
    maxAskHumanKindMismatchRate: optionalNumberInRange(options.maxAskHumanKindMismatchRate, "maxAskHumanKindMismatchRate", 0),
    maxAskHumanActionMismatchRate: optionalNumberInRange(
      options.maxAskHumanActionMismatchRate,
      "maxAskHumanActionMismatchRate",
      0,
    ),
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
  const unsafeProfileMismatchCount = countWhere(
    recentRecords,
    (record) => record.profileMatch === false && record.profileDriftTolerated !== true,
  );
  const targetFilesMismatchCount = countWhere(recentRecords, (record) => record.targetFilesMatch === false);
  const unsafeTargetFilesMismatchCount = countWhere(
    recentRecords,
    (record) => record.targetFilesMatch === false && record.targetFilesDriftTolerated !== true,
  );
  const humanNeededMismatchCount = countWhere(recentRecords, (record) => record.humanNeededMatch === false);
  const askHumanKindMismatchCount = countWhere(recentRecords, (record) => record.kindMatch === false);
  const askHumanActionMismatchCount = countWhere(recentRecords, (record) => record.recommendedActionMatch === false);
  const unsafeAskHumanActionMismatchCount = countWhere(
    recentRecords,
    (record) => record.recommendedActionMatch === false && record.recommendedActionDriftTolerated !== true,
  );
  const askHumanOptionsMismatchCount = countWhere(recentRecords, (record) => record.optionsMatch === false);

  const profileMismatchRate = ratio(profileMismatchCount, sampleSize);
  const unsafeProfileMismatchRate = ratio(unsafeProfileMismatchCount, sampleSize);
  const targetFilesMismatchRate = ratio(targetFilesMismatchCount, sampleSize);
  const unsafeTargetFilesMismatchRate = ratio(unsafeTargetFilesMismatchCount, sampleSize);
  const humanNeededMismatchRate = ratio(humanNeededMismatchCount, sampleSize);
  const askHumanKindMismatchRate = ratio(askHumanKindMismatchCount, sampleSize);
  const askHumanActionMismatchRate = ratio(askHumanActionMismatchCount, sampleSize);
  const unsafeAskHumanActionMismatchRate = ratio(unsafeAskHumanActionMismatchCount, sampleSize);
  const askHumanOptionsMismatchRate = ratio(askHumanOptionsMismatchCount, sampleSize);

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
  if (unsafeProfileMismatchRate !== null && unsafeProfileMismatchRate > options.maxProfileMismatchRate) {
    blockingReasons.push(`unsafe_profile_mismatch_rate:${unsafeProfileMismatchRate}`);
  }
  if (unsafeTargetFilesMismatchRate !== null && unsafeTargetFilesMismatchRate > options.maxTargetFilesMismatchRate) {
    blockingReasons.push(`unsafe_target_files_mismatch_rate:${unsafeTargetFilesMismatchRate}`);
  }
  if (humanNeededMismatchRate !== null && humanNeededMismatchRate > options.maxHumanNeededMismatchRate) {
    blockingReasons.push(`human_needed_mismatch_rate:${humanNeededMismatchRate}`);
  }
  if (
    options.module === "intake.ask_human" &&
    askHumanKindMismatchRate !== null &&
    askHumanKindMismatchRate > options.maxAskHumanKindMismatchRate
  ) {
    blockingReasons.push(`ask_human_kind_mismatch_rate:${askHumanKindMismatchRate}`);
  }
  if (
    options.module === "intake.ask_human" &&
    unsafeAskHumanActionMismatchRate !== null &&
    unsafeAskHumanActionMismatchRate > options.maxAskHumanActionMismatchRate
  ) {
    blockingReasons.push(`unsafe_ask_human_action_mismatch_rate:${unsafeAskHumanActionMismatchRate}`);
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
    unsafeProfileMismatchCount,
    targetFilesMismatchCount,
    unsafeTargetFilesMismatchCount,
    humanNeededMismatchCount,
    askHumanKindMismatchCount,
    askHumanActionMismatchCount,
    unsafeAskHumanActionMismatchCount,
    askHumanOptionsMismatchCount,
    profileMismatchRate,
    unsafeProfileMismatchRate,
    targetFilesMismatchRate,
    unsafeTargetFilesMismatchRate,
    humanNeededMismatchRate,
    askHumanKindMismatchRate,
    askHumanActionMismatchRate,
    unsafeAskHumanActionMismatchRate,
    askHumanOptionsMismatchRate,
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
      profileDriftKind: record.profileDriftKind,
      profileDriftTolerated: record.profileDriftTolerated,
      targetFilesMatch: record.targetFilesMatch,
      targetFilesDriftKind: record.targetFilesDriftKind,
      targetFilesDriftTolerated: record.targetFilesDriftTolerated,
      humanNeededMatch: record.humanNeededMatch,
      kindMatch: record.kindMatch,
      recommendedActionMatch: record.recommendedActionMatch,
      recommendedActionDriftKind: record.recommendedActionDriftKind,
      recommendedActionDriftTolerated: record.recommendedActionDriftTolerated,
      optionsMatch: record.optionsMatch,
      machineReadableMarkersShadow: record.machineReadableMarkersShadow,
    })),
  };
}

module.exports = {
  normalizeGateOptions,
  evaluateProviderRolloutGate,
};
