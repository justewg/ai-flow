"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  compareInterpretationResults,
  compareAskHumanResults,
} = require("../src/intake_compare");

test("compareInterpretationResults computes decision and target file deltas", () => {
  const compare = compareInterpretationResults(
    {
      decision: "standard",
      candidateTargetFiles: ["a.txt"],
      confidence: { score: 0.8 },
    },
    {
      decision: "human_needed",
      candidateTargetFiles: ["b.txt"],
      confidence: { score: 0.4 },
    },
    { compareMode: "dry_run" },
  );

  assert.equal(compare.profileMatch, false);
  assert.equal(compare.targetFilesMatch, false);
  assert.equal(compare.humanNeededMatch, false);
  assert.equal(compare.compareSummary, "interpretation_profile_mismatch");
});

test("compareInterpretationResults marks same-profile subset target drift as tolerated", () => {
  const compare = compareInterpretationResults(
    {
      decision: "standard",
      candidateTargetFiles: ["AndroidManifest.xml", "MainActivity.kt"],
      confidence: { score: 0.9 },
    },
    {
      decision: "standard",
      candidateTargetFiles: ["MainActivity.kt"],
      confidence: { score: 0.8 },
    },
    { compareMode: "dry_run" },
  );

  assert.equal(compare.targetFilesMatch, false);
  assert.equal(compare.targetFilesDriftKind, "shadow_subset");
  assert.equal(compare.targetFilesDriftTolerated, true);
  assert.equal(compare.compareSummary, "interpretation_target_files_tolerated");
});

test("compareInterpretationResults marks blocked target expansion as tolerated", () => {
  const compare = compareInterpretationResults(
    {
      decision: "blocked",
      candidateTargetFiles: ["status.md"],
      confidence: { score: 0.9 },
    },
    {
      decision: "blocked",
      candidateTargetFiles: ["MainActivity.kt", "status.md"],
      confidence: { score: 0.8 },
    },
    { compareMode: "dry_run" },
  );

  assert.equal(compare.targetFilesMatch, false);
  assert.equal(compare.targetFilesDriftKind, "blocked_scope_drift");
  assert.equal(compare.targetFilesDriftTolerated, true);
  assert.equal(compare.compareSummary, "interpretation_target_files_tolerated");
});

test("compareInterpretationResults marks conservative shadow profile drift as tolerated", () => {
  const compare = compareInterpretationResults(
    {
      decision: "micro",
      candidateTargetFiles: ["MainActivity.kt", "index.html"],
      confidence: { score: 0.91 },
    },
    {
      decision: "standard",
      candidateTargetFiles: ["MainActivity.kt", "index.html"],
      confidence: { score: 0.92 },
    },
    { compareMode: "dry_run" },
  );

  assert.equal(compare.profileMatch, false);
  assert.equal(compare.profileDriftKind, "conservative_shadow");
  assert.equal(compare.profileDriftTolerated, true);
  assert.equal(compare.compareSummary, "interpretation_profile_tolerated");
});

test("compareInterpretationResults keeps aggressive shadow profile drift unsafe", () => {
  const compare = compareInterpretationResults(
    {
      decision: "standard",
      candidateTargetFiles: ["MainActivity.kt", "index.html"],
      confidence: { score: 0.91 },
    },
    {
      decision: "micro",
      candidateTargetFiles: ["MainActivity.kt", "index.html"],
      confidence: { score: 0.92 },
    },
    { compareMode: "dry_run" },
  );

  assert.equal(compare.profileMatch, false);
  assert.equal(compare.profileDriftKind, "aggressive_shadow");
  assert.equal(compare.profileDriftTolerated, false);
  assert.equal(compare.compareSummary, "interpretation_profile_mismatch");
});

test("compareAskHumanResults computes body and structure drift", () => {
  const compare = compareAskHumanResults(
    {
      kind: "QUESTION",
      recommendedAction: "continue",
      body: "Нужно уточнение по компоненту. Какой экран править?",
      options: ["Продолжай"],
    },
    {
      kind: "BLOCKER",
      recommendedAction: "clarify",
      body: "Не удалось определить компонент.",
      options: ["Уточни"],
    },
    { compareMode: "shadow" },
  );

  assert.equal(compare.kindMatch, false);
  assert.equal(compare.recommendedActionMatch, false);
  assert.equal(compare.machineReadableMarkersShadow, true);
  assert.equal(compare.compareSummary, "ask_human_kind_mismatch");
});

test("compareInterpretationResults tolerates shadow provider error artifact", () => {
  const compare = compareInterpretationResults(
    {
      decision: "standard",
      candidateTargetFiles: ["app/Main.kt"],
      confidence: { score: 0.6 },
    },
    {
      _shadowProviderError: {
        errorClass: "schema_invalid_output",
      },
    },
    { compareMode: "dry_run" },
  );

  assert.equal(compare.schemaValidShadow, false);
  assert.match(compare.compareSummary, /^interpretation_shadow_invalid/);
});

test("compareAskHumanResults tolerates shadow provider error artifact", () => {
  const compare = compareAskHumanResults(
    {
      kind: "QUESTION",
      recommendedAction: "clarify",
      body: "Что именно исправить?",
      options: [],
    },
    {
      _shadowProviderError: {
        errorClass: "empty_output",
      },
    },
    { compareMode: "shadow" },
  );

  assert.equal(compare.schemaValidShadow, false);
  assert.match(compare.compareSummary, /^ask_human_shadow_invalid/);
});
