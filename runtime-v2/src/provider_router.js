"use strict";

const { ValidationError } = require("./errors");
const { MODULES, PROVIDERS } = require("./provider_contract");

const MODULE_GROUPS = {
  "intake.interpretation": "intake",
  "intake.ask_human": "intake",
  "planning.spec_enrichment": "planning",
  "execution.micro": "execution",
  "execution.standard": "execution",
  "review.summary": "review",
};

const DEFAULT_ENVELOPE = {
  timeoutMs: 120000,
  fallbackAllowed: true,
  budgetKey: null,
};

function assertProvider(value, fieldName) {
  const normalized = typeof value === "string" ? value.trim() : "";
  if (!PROVIDERS.has(normalized)) {
    throw new ValidationError(`${fieldName} has unsupported provider: ${normalized || value}`, { fieldName });
  }
  return normalized;
}

function assertModule(value) {
  const normalized = typeof value === "string" ? value.trim() : "";
  if (!MODULES.has(normalized)) {
    throw new ValidationError(`module has unsupported value: ${normalized || value}`, { fieldName: "module" });
  }
  return normalized;
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

function optionalBoolean(value, defaultValue = false) {
  if (value === undefined || value === null) {
    return defaultValue;
  }
  return value === true;
}

function optionalPositiveInteger(value, fieldName, defaultValue) {
  if (value === undefined || value === null || value === "") {
    return defaultValue;
  }
  if (!Number.isInteger(value) || value <= 0) {
    throw new ValidationError(`${fieldName} must be a positive integer`, { fieldName });
  }
  return value;
}

function moduleTail(moduleName) {
  const index = moduleName.indexOf(".");
  return index >= 0 ? moduleName.slice(index + 1) : moduleName;
}

function moduleProviderConfig(config, moduleName) {
  const group = MODULE_GROUPS[moduleName];
  const tail = moduleTail(moduleName);
  const providers = optionalObject(config.providers, "providers");
  const groupConfig = optionalObject(providers[group], `providers.${group}`);
  const envelopes = optionalObject(config.envelopes, "envelopes");
  const moduleEnvelope = optionalObject(envelopes[moduleName], `envelopes.${moduleName}`);

  return {
    group,
    configuredProvider: groupConfig[tail] || providers.default || "codex",
    fallbackProvider: groupConfig.fallback || providers.default || "codex",
    envelope: {
      timeoutMs: optionalPositiveInteger(moduleEnvelope.timeoutMs, `envelopes.${moduleName}.timeoutMs`, DEFAULT_ENVELOPE.timeoutMs),
      fallbackAllowed: optionalBoolean(moduleEnvelope.fallbackAllowed, DEFAULT_ENVELOPE.fallbackAllowed),
      budgetKey: typeof moduleEnvelope.budgetKey === "string" && moduleEnvelope.budgetKey.trim() !== "" ? moduleEnvelope.budgetKey.trim() : null,
    },
  };
}

function normalizeProviderRoutingConfig(input = {}) {
  const config = optionalObject(input, "providerRoutingConfig");
  const providers = optionalObject(config.providers, "providers");
  const normalized = {
    providers: {
      default: assertProvider(providers.default || "codex", "providers.default"),
      intake: optionalObject(providers.intake, "providers.intake"),
      planning: optionalObject(providers.planning, "providers.planning"),
      execution: optionalObject(providers.execution, "providers.execution"),
      review: optionalObject(providers.review, "providers.review"),
    },
    routing: {
      useAutoRouter: optionalBoolean(optionalObject(config.routing, "routing").useAutoRouter, false),
    },
    envelopes: optionalObject(config.envelopes, "envelopes"),
  };

  for (const groupName of ["intake", "planning", "execution", "review"]) {
    const groupConfig = normalized.providers[groupName];
    for (const [key, value] of Object.entries(groupConfig)) {
      if (key === "fallback") {
        groupConfig[key] = assertProvider(value, `providers.${groupName}.${key}`);
      } else if (typeof value === "string") {
        groupConfig[key] = assertProvider(value, `providers.${groupName}.${key}`);
      }
    }
  }

  return normalized;
}

function chooseAutoProvider(moduleName, hints = {}, defaultProvider = "codex") {
  const taskProfile = typeof hints.taskProfile === "string" ? hints.taskProfile.trim() : "";
  const reasoningHeavy = hints.reasoningHeavy === true;
  const ambiguousHumanText = hints.ambiguousHumanText === true;

  if (moduleName === "execution.micro") {
    return { provider: "codex", reason: "auto_router_micro_default_codex" };
  }
  if (moduleName === "review.summary") {
    return { provider: "claude", reason: "auto_router_review_summary_claude" };
  }
  if (moduleName === "intake.interpretation" || moduleName === "intake.ask_human") {
    if (ambiguousHumanText || reasoningHeavy) {
      return { provider: "claude", reason: "auto_router_intake_ambiguous_or_reasoning_heavy" };
    }
  }
  if (taskProfile === "micro") {
    return { provider: "codex", reason: "auto_router_task_profile_micro" };
  }
  if (taskProfile === "standard" && reasoningHeavy) {
    return { provider: "claude", reason: "auto_router_task_profile_standard_reasoning_heavy" };
  }
  return { provider: defaultProvider, reason: "auto_router_default_provider" };
}

function resolveProviderRoute(input, configInput = {}) {
  const request = optionalObject(input, "providerRouteInput");
  const moduleName = assertModule(request.module);
  const config = normalizeProviderRoutingConfig(configInput);
  const moduleConfig = moduleProviderConfig(config, moduleName);
  const preferredProvider =
    request.preferredProvider === undefined || request.preferredProvider === null || request.preferredProvider === ""
      ? moduleConfig.configuredProvider
      : assertProvider(request.preferredProvider, "preferredProvider");

  let effectiveProvider = preferredProvider;
  let decisionReason = "configured_provider";

  if (preferredProvider === "auto" || (config.routing.useAutoRouter && request.useAutoRouter === true)) {
    const autoDecision = chooseAutoProvider(moduleName, request.hints || {}, config.providers.default);
    effectiveProvider = autoDecision.provider;
    decisionReason = autoDecision.reason;
  }

  const fallbackProvider = moduleConfig.envelope.fallbackAllowed
    ? moduleConfig.fallbackProvider
    : null;

  return {
    module: moduleName,
    group: moduleConfig.group,
    requestedProvider: preferredProvider,
    effectiveProvider,
    fallbackProvider,
    timeoutMs: moduleConfig.envelope.timeoutMs,
    fallbackAllowed: moduleConfig.envelope.fallbackAllowed,
    budgetKey: moduleConfig.envelope.budgetKey,
    decisionReason,
  };
}

module.exports = {
  MODULE_GROUPS,
  normalizeProviderRoutingConfig,
  resolveProviderRoute,
};
