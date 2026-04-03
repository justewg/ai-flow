"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  normalizeProviderCompareConfig,
  resolveProviderCompareMode,
} = require("../src/provider_compare");

test("normalizeProviderCompareConfig normalizes compare config", () => {
  const config = normalizeProviderCompareConfig({
    compare: {
      "intake.interpretation": {
        mode: "dry_run",
        shadowProvider: "claude",
      },
    },
  });

  assert.equal(config["intake.interpretation"].mode, "dry_run");
  assert.equal(config["intake.interpretation"].shadowProvider, "claude");
});

test("resolveProviderCompareMode enables dry-run compare", () => {
  const verdict = resolveProviderCompareMode(
    { module: "intake.ask_human" },
    {
      compare: {
        "intake.ask_human": {
          mode: "shadow",
          shadowProvider: "claude",
        },
      },
    },
  );

  assert.equal(verdict.enabled, true);
  assert.equal(verdict.mode, "shadow");
  assert.equal(verdict.shadowProvider, "claude");
  assert.equal(verdict.publishDecision, false);
});
