"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  normalizeProviderRoutingConfig,
  resolveProviderRoute,
} = require("../src/provider_router");

test("normalizeProviderRoutingConfig normalizes provider config", () => {
  const config = normalizeProviderRoutingConfig({
    providers: {
      default: "codex",
      intake: {
        interpretation: "claude",
        ask_human: "claude",
        fallback: "codex",
      },
    },
    routing: {
      useAutoRouter: true,
    },
    envelopes: {
      "intake.interpretation": {
        timeoutMs: 45000,
        fallbackAllowed: true,
        budgetKey: "intake",
      },
    },
  });

  assert.equal(config.providers.default, "codex");
  assert.equal(config.providers.intake.interpretation, "claude");
  assert.equal(config.routing.useAutoRouter, true);
});

test("resolveProviderRoute uses configured provider when not auto", () => {
  const route = resolveProviderRoute(
    {
      module: "execution.standard",
    },
    {
      providers: {
        default: "codex",
        execution: {
          standard: "codex",
          fallback: "codex",
        },
      },
    },
  );

  assert.equal(route.effectiveProvider, "codex");
  assert.equal(route.decisionReason, "configured_provider");
});

test("resolveProviderRoute applies auto-router heuristics", () => {
  const route = resolveProviderRoute(
    {
      module: "intake.interpretation",
      preferredProvider: "auto",
      hints: {
        ambiguousHumanText: true,
      },
    },
    {
      providers: {
        default: "codex",
        intake: {
          interpretation: "auto",
          fallback: "codex",
        },
      },
      routing: {
        useAutoRouter: true,
      },
    },
  );

  assert.equal(route.effectiveProvider, "claude");
  assert.equal(route.decisionReason, "auto_router_intake_ambiguous_or_reasoning_heavy");
  assert.equal(route.fallbackProvider, "codex");
});

test("resolveProviderRoute keeps execution.micro on codex in auto mode", () => {
  const route = resolveProviderRoute(
    {
      module: "execution.micro",
      preferredProvider: "auto",
      hints: {
        taskProfile: "micro",
      },
    },
    {
      providers: {
        default: "codex",
        execution: {
          micro: "auto",
          fallback: "codex",
        },
      },
      routing: {
        useAutoRouter: true,
      },
    },
  );

  assert.equal(route.effectiveProvider, "codex");
  assert.equal(route.decisionReason, "auto_router_micro_default_codex");
});

test("resolveProviderRoute accepts explicit local provider", () => {
  const route = resolveProviderRoute(
    {
      module: "intake.ask_human",
      preferredProvider: "local",
    },
    {
      providers: {
        default: "codex",
        intake: {
          ask_human: "codex",
          fallback: "codex",
        },
      },
    },
  );

  assert.equal(route.requestedProvider, "local");
  assert.equal(route.effectiveProvider, "local");
  assert.equal(route.decisionReason, "configured_provider");
});
