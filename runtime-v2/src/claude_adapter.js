"use strict";

const { ValidationError } = require("./errors");
const { resolveProviderRoute } = require("./provider_router");

function assertNonEmptyString(value, fieldName) {
  if (typeof value !== "string" || value.trim() === "") {
    throw new ValidationError(`${fieldName} must be a non-empty string`, { fieldName });
  }
  return value.trim();
}

function buildClaudeInvocationPlan(input, config = {}) {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw new ValidationError("claude adapter input must be an object");
  }

  const promptFile = assertNonEmptyString(input.promptFile, "promptFile");
  const responseFile = assertNonEmptyString(input.responseFile, "responseFile");
  const moduleName = assertNonEmptyString(input.module, "module");
  const taskRepo = typeof input.taskRepo === "string" && input.taskRepo.trim() !== "" ? input.taskRepo.trim() : null;

  const route = resolveProviderRoute(
    {
      module: moduleName,
      preferredProvider: input.preferredProvider,
      hints: input.hints || {},
      useAutoRouter: input.useAutoRouter === true,
    },
    config,
  );

  if (route.effectiveProvider !== "claude") {
    throw new ValidationError("claude adapter can only build invocation for claude route", {
      module: moduleName,
      effectiveProvider: route.effectiveProvider,
    });
  }

  return {
    provider: "claude",
    module: moduleName,
    mode: "provider-json",
    invocation: {
      provider: "claude",
      transport: "runner_managed",
      runner: ".flow/shared/tools/providers/claude/run_claude_provider.mjs",
      promptFile,
      responseFile,
      taskRepo,
    },
    route,
    telemetry: {
      requestedProvider: route.requestedProvider,
      effectiveProvider: "claude",
      fallbackProvider: route.fallbackProvider,
      decisionReason: route.decisionReason,
      timeoutMs: route.timeoutMs,
      budgetKey: route.budgetKey,
    },
  };
}

module.exports = {
  buildClaudeInvocationPlan,
};
