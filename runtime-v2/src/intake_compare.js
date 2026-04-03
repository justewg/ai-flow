"use strict";

function providerError(input) {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    return null;
  }
  const providerErrorValue = input._shadowProviderError;
  if (!providerErrorValue || typeof providerErrorValue !== "object" || Array.isArray(providerErrorValue)) {
    return null;
  }
  return providerErrorValue;
}

function normalizeStringArray(value) {
  if (!Array.isArray(value)) {
    return [];
  }
  return value
    .filter((item) => typeof item === "string")
    .map((item) => item.trim())
    .filter(Boolean)
    .sort();
}

function hasExplanationText(text) {
  if (typeof text !== "string") {
    return false;
  }
  return /(понят|не удалось|не смог|missing|understood|clarif|уточн|component|файл|компонент)/i.test(text);
}

function hasQuestionText(text) {
  return typeof text === "string" && /[?؟]/.test(text);
}

function compareInterpretationResults(primary, shadow, options = {}) {
  const primaryError = providerError(primary);
  const shadowError = providerError(shadow);
  const primaryFiles = normalizeStringArray(primary?.candidateTargetFiles);
  const shadowFiles = normalizeStringArray(shadow?.candidateTargetFiles);
  const primaryDecision = typeof primary?.decision === "string" ? primary.decision : null;
  const shadowDecision = typeof shadow?.decision === "string" ? shadow.decision : null;
  const primaryConfidence = typeof primary?.confidence?.score === "number" ? primary.confidence.score : null;
  const shadowConfidence = typeof shadow?.confidence?.score === "number" ? shadow.confidence.score : null;
  const schemaValidPrimary = options.schemaValidPrimary !== false && primaryError === null && primaryDecision !== null;
  const schemaValidShadow = options.schemaValidShadow !== false && shadowError === null && shadowDecision !== null;
  const profileMatch = primaryDecision !== null && shadowDecision !== null ? primaryDecision === shadowDecision : null;
  const targetFilesMatch =
    primaryDecision !== null && shadowDecision !== null ? JSON.stringify(primaryFiles) === JSON.stringify(shadowFiles) : null;
  const humanNeededMatch =
    primaryDecision !== null && shadowDecision !== null
      ? (primaryDecision === "human_needed") === (shadowDecision === "human_needed")
      : null;

  return {
    module: "intake.interpretation",
    compareMode: options.compareMode || "disabled",
    primaryProvider: options.primaryProvider || "local",
    shadowProvider: options.shadowProvider || "claude",
    schemaValidPrimary,
    schemaValidShadow,
    profileMatch,
    targetFilesMatch,
    humanNeededMatch,
    confidenceDelta:
      primaryConfidence !== null && shadowConfidence !== null ? Number((shadowConfidence - primaryConfidence).toFixed(6)) : null,
    compareSummary:
      schemaValidPrimary === false
        ? "interpretation_primary_invalid"
        : schemaValidShadow === false
          ? `interpretation_shadow_invalid${shadowError?.errorClass ? `:${shadowError.errorClass}` : ""}`
        : profileMatch === true && targetFilesMatch === true
        ? "interpretation_match"
        : profileMatch === false
          ? "interpretation_profile_mismatch"
          : targetFilesMatch === false
            ? "interpretation_target_files_mismatch"
            : "interpretation_inconclusive",
    publishDecision: false,
    primaryDecision,
    shadowDecision,
    primaryTargetFiles: primaryFiles,
    shadowTargetFiles: shadowFiles,
    shadowError,
  };
}

function compareAskHumanResults(primary, shadow, options = {}) {
  const primaryError = providerError(primary);
  const shadowError = providerError(shadow);
  const primaryBody = typeof primary?.body === "string" ? primary.body.trim() : "";
  const shadowBody = typeof shadow?.body === "string" ? shadow.body.trim() : "";
  const primaryOptions = normalizeStringArray(primary?.options);
  const shadowOptions = normalizeStringArray(shadow?.options);
  const schemaValidPrimary =
    options.schemaValidPrimary !== false &&
    primaryError === null &&
    typeof primary?.kind === "string" &&
    typeof primary?.recommendedAction === "string";
  const schemaValidShadow =
    options.schemaValidShadow !== false &&
    shadowError === null &&
    typeof shadow?.kind === "string" &&
    typeof shadow?.recommendedAction === "string";
  const kindMatch =
    typeof primary?.kind === "string" && typeof shadow?.kind === "string" ? primary.kind === shadow.kind : null;
  const recommendedActionMatch =
    typeof primary?.recommendedAction === "string" && typeof shadow?.recommendedAction === "string"
      ? primary.recommendedAction === shadow.recommendedAction
      : null;

  return {
    module: "intake.ask_human",
    compareMode: options.compareMode || "disabled",
    primaryProvider: options.primaryProvider || "local",
    shadowProvider: options.shadowProvider || "claude",
    schemaValidPrimary,
    schemaValidShadow,
    machineReadableMarkersPrimary: typeof primary?.kind === "string" && typeof primary?.recommendedAction === "string",
    machineReadableMarkersShadow: typeof shadow?.kind === "string" && typeof shadow?.recommendedAction === "string",
    kindMatch,
    recommendedActionMatch,
    optionsMatch: JSON.stringify(primaryOptions) === JSON.stringify(shadowOptions),
    bodyLengthDelta: shadowBody.length - primaryBody.length,
    explanationCompletenessPrimary: hasExplanationText(primaryBody),
    explanationCompletenessShadow: hasExplanationText(shadowBody),
    specificityQuestionPrimary: hasQuestionText(primaryBody),
    specificityQuestionShadow: hasQuestionText(shadowBody),
    compareSummary:
      schemaValidPrimary === false
        ? "ask_human_primary_invalid"
        : schemaValidShadow === false
          ? `ask_human_shadow_invalid${shadowError?.errorClass ? `:${shadowError.errorClass}` : ""}`
        : kindMatch === true && recommendedActionMatch === true
        ? "ask_human_match"
        : kindMatch === false
          ? "ask_human_kind_mismatch"
          : recommendedActionMatch === false
            ? "ask_human_action_mismatch"
            : "ask_human_inconclusive",
      publishDecision: false,
    shadowError,
  };
}

module.exports = {
  compareInterpretationResults,
  compareAskHumanResults,
};
