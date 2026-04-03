"use strict";

const { ValidationError } = require("./errors");
const { resolveProviderRoute } = require("./provider_router");

function assertNonEmptyString(value, fieldName) {
  if (typeof value !== "string" || value.trim() === "") {
    throw new ValidationError(`${fieldName} must be a non-empty string`, { fieldName });
  }
  return value.trim();
}

function buildCodexInvocationPlan(input, config = {}) {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw new ValidationError("codex adapter input must be an object");
  }

  const taskRepo = assertNonEmptyString(input.taskRepo, "taskRepo");
  const responseFile = assertNonEmptyString(input.responseFile, "responseFile");
  const moduleName = assertNonEmptyString(input.module, "module");
  const dangerBypass = input.dangerouslyBypassSandbox === true;

  const route = resolveProviderRoute(
    {
      module: moduleName,
      preferredProvider: input.preferredProvider,
      hints: input.hints || {},
      useAutoRouter: input.useAutoRouter === true,
    },
    config,
  );

  if (route.effectiveProvider !== "codex") {
    throw new ValidationError("codex adapter can only build invocation for codex route", {
      module: moduleName,
      effectiveProvider: route.effectiveProvider,
    });
  }

  const argv = ["codex", "exec", "-C", taskRepo];
  if (dangerBypass) {
    argv.push("--dangerously-bypass-approvals-and-sandbox");
  } else {
    argv.push("--full-auto");
  }
  argv.push("--output-last-message", responseFile);
  argv.push("-");

  return {
    provider: "codex",
    module: moduleName,
    mode: dangerBypass ? "danger-full-access" : "full-auto",
    argv,
    route,
    telemetry: {
      requestedProvider: route.requestedProvider,
      effectiveProvider: "codex",
      fallbackProvider: route.fallbackProvider,
      decisionReason: route.decisionReason,
      timeoutMs: route.timeoutMs,
      budgetKey: route.budgetKey,
    },
  };
}

module.exports = {
  buildCodexInvocationPlan,
};
