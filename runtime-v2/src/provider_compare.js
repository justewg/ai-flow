"use strict";

const { ValidationError } = require("./errors");
const { MODULES, PROVIDERS } = require("./provider_contract");

const COMPARE_MODES = new Set(["disabled", "dry_run", "shadow", "live"]);

function assertModule(value) {
  const normalized = typeof value === "string" ? value.trim() : "";
  if (!MODULES.has(normalized)) {
    throw new ValidationError(`module has unsupported value: ${normalized || value}`, { fieldName: "module" });
  }
  return normalized;
}

function assertProvider(value, fieldName) {
  const normalized = typeof value === "string" ? value.trim() : "";
  if (!PROVIDERS.has(normalized) || normalized === "auto" || normalized === "local") {
    throw new ValidationError(`${fieldName} has unsupported compare provider: ${normalized || value}`, { fieldName });
  }
  return normalized;
}

function assertMode(value, fieldName) {
  const normalized = typeof value === "string" ? value.trim().toLowerCase() : "";
  if (!COMPARE_MODES.has(normalized)) {
    throw new ValidationError(`${fieldName} has unsupported compare mode: ${normalized || value}`, { fieldName });
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

function normalizeProviderCompareConfig(input = {}) {
  const config = optionalObject(input, "providerRoutingConfig");
  const compare = optionalObject(config.compare, "compare");
  const normalized = {};

  for (const [moduleName, rawConfig] of Object.entries(compare)) {
    const normalizedModule = assertModule(moduleName);
    const moduleConfig = optionalObject(rawConfig, `compare.${moduleName}`);
    normalized[normalizedModule] = {
      mode: assertMode(moduleConfig.mode || "disabled", `compare.${moduleName}.mode`),
      shadowProvider:
        moduleConfig.shadowProvider === undefined || moduleConfig.shadowProvider === null || moduleConfig.shadowProvider === ""
          ? "claude"
          : assertProvider(moduleConfig.shadowProvider, `compare.${moduleName}.shadowProvider`),
      publishDecision: moduleConfig.publishDecision === true,
    };
  }

  return normalized;
}

function resolveProviderCompareMode(input, configInput = {}) {
  const request = optionalObject(input, "providerCompareInput");
  const moduleName = assertModule(request.module);
  const compareConfig = normalizeProviderCompareConfig(configInput);
  const moduleConfig = compareConfig[moduleName] || {
    mode: "disabled",
    shadowProvider: "claude",
    publishDecision: false,
  };

  return {
    module: moduleName,
    mode: moduleConfig.mode,
    enabled: moduleConfig.mode === "dry_run" || moduleConfig.mode === "shadow",
    shadowProvider: moduleConfig.shadowProvider,
    publishDecision: moduleConfig.publishDecision === true && moduleConfig.mode === "live",
  };
}

module.exports = {
  COMPARE_MODES,
  normalizeProviderCompareConfig,
  resolveProviderCompareMode,
};
