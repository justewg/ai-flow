#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { query, AbortError } from "@anthropic-ai/claude-agent-sdk";

const require = createRequire(import.meta.url);

function parseArgs(argv) {
  const args = {
    module: "",
    requestFile: "",
    responseFile: "",
    taskRepo: "",
    taskId: "",
    issueNumber: null,
    toolkitRoot: "",
    timeoutMs: 120000,
    pathToClaudeCodeExecutable: process.env.CLAUDE_CODE_EXECUTABLE || "",
  };

  for (let index = 2; index < argv.length; index += 1) {
    const token = argv[index];
    const next = argv[index + 1];
    if (token === "--module") {
      args.module = next;
      index += 1;
    } else if (token === "--request-file") {
      args.requestFile = next;
      index += 1;
    } else if (token === "--response-file") {
      args.responseFile = next;
      index += 1;
    } else if (token === "--task-repo") {
      args.taskRepo = next;
      index += 1;
    } else if (token === "--task-id") {
      args.taskId = next;
      index += 1;
    } else if (token === "--issue-number") {
      args.issueNumber = next;
      index += 1;
    } else if (token === "--toolkit-root") {
      args.toolkitRoot = next;
      index += 1;
    } else if (token === "--timeout-ms") {
      args.timeoutMs = Number.parseInt(next, 10);
      index += 1;
    } else if (token === "--path-to-claude-code-executable") {
      args.pathToClaudeCodeExecutable = next;
      index += 1;
    }
  }

  if (!args.module || !args.requestFile || !args.responseFile || !args.taskId || !args.toolkitRoot) {
    throw new Error(
      "Usage: run_claude_provider.mjs --module <module> --request-file <path> --response-file <path> --task-id <id> [--issue-number <n>] --toolkit-root <path> [--task-repo <path>] [--timeout-ms <ms>] [--path-to-claude-code-executable <path>]",
    );
  }
  if (!Number.isInteger(args.timeoutMs) || args.timeoutMs <= 0) {
    throw new Error("timeout-ms must be a positive integer");
  }
  return args;
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function writeJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function loadToolkitContracts(toolkitRoot) {
  const intakeContractPath = path.resolve(toolkitRoot, "runtime-v2/src/intake_contract.js");
  const providerContractPath = path.resolve(toolkitRoot, "runtime-v2/src/provider_contract.js");
  return {
    ...require(intakeContractPath),
    ...require(providerContractPath),
  };
}

function schemaForModule(moduleName) {
  if (moduleName === "intake.interpretation") {
    return {
      type: "object",
      additionalProperties: false,
      required: [
        "decision",
        "decisionReason",
        "interpretedIntent",
        "confidence",
        "candidateTargetFiles",
        "rationale",
        "askHumanQuestion",
      ],
      properties: {
        decision: { type: "string", enum: ["micro", "standard", "human_needed", "blocked"] },
        decisionReason: { type: "string" },
        interpretedIntent: { type: "string" },
        confidence: {
          type: "object",
          additionalProperties: false,
          required: ["label", "score"],
          properties: {
            label: { type: "string" },
            score: { type: "number" },
          },
        },
        candidateTargetFiles: { type: "array", items: { type: "string" } },
        rationale: { type: "array", items: { type: "string" } },
        askHumanQuestion: { anyOf: [{ type: "string" }, { type: "null" }] },
      },
    };
  }

  if (moduleName === "intake.ask_human") {
    return {
      type: "object",
      additionalProperties: false,
      required: ["kind", "body", "expectsReply", "recommendedAction", "options"],
      properties: {
        kind: { type: "string", enum: ["QUESTION", "BLOCKER"] },
        body: { type: "string" },
        expectsReply: { type: "boolean" },
        recommendedAction: { type: "string", enum: ["continue", "clarify", "finalize"] },
        options: { type: "array", items: { type: "string" } },
      },
    };
  }

  throw new Error(`Unsupported Claude intake module: ${moduleName}`);
}

function systemPromptForModule(moduleName) {
  if (moduleName === "intake.interpretation") {
    return [
      "You are a narrow AI Flow v2 intake worker.",
      "Return exactly one JSON object matching the provided schema.",
      "Do not use tools if a direct structured answer is possible.",
      "If ambiguity is unsafe, choose human_needed instead of guessing.",
      "Do not widen file scope from weak hints.",
      "Do not require an explicit file path if the task is a narrow UI/content tweak and repository hints already identify a likely implementation surface.",
      "Prefer micro or standard over human_needed when the issue is concrete, bounded, and repository hints point to a plausible app/module boundary.",
    ].join(" ");
  }

  if (moduleName === "intake.ask_human") {
    return [
      "You are a narrow AI Flow v2 ask-human worker.",
      "Return exactly one JSON object matching the provided schema.",
      "Do not use tools if a direct structured answer is possible.",
      "Keep machine-readable fields intact and ask the minimum clarifying question needed.",
      "Do not add prose outside JSON.",
    ].join(" ");
  }

  return "Return exactly one JSON object matching the provided schema. Do not use tools if a direct structured answer is possible.";
}

function tokenUsageFromUsage(usage) {
  if (!usage || typeof usage !== "object") {
    return null;
  }
  let total = 0;
  let found = false;
  for (const [key, value] of Object.entries(usage)) {
    if (typeof value === "number" && Number.isFinite(value) && value >= 0 && /tokens?/i.test(key)) {
      total += value;
      found = true;
    }
  }
  return found ? total : null;
}

function buildErrorResult({ requestId, taskId, moduleName, errorClass, errorMessage, latencyMs, tokenUsage, estimatedCost }) {
  return {
    requestId,
    taskId,
    module: moduleName,
    provider: "claude",
    outcome: "error",
    outputText: null,
    structuredOutput: {},
    errorClass,
    errorMessage: errorMessage || null,
    latencyMs: Number.isInteger(latencyMs) && latencyMs >= 0 ? latencyMs : null,
    tokenUsage: Number.isInteger(tokenUsage) && tokenUsage >= 0 ? tokenUsage : null,
    estimatedCost: typeof estimatedCost === "number" && Number.isFinite(estimatedCost) && estimatedCost >= 0 ? estimatedCost : null,
    fallbackFromProvider: null,
    meta: {},
  };
}

function classifyClaudeExecutionError(errorLike) {
  const message = String(errorLike?.message || errorLike || "");
  const normalized = message.toLowerCase();
  if (message.includes("claude_provider_timeout")) {
    return "timeout";
  }
  if (normalized.includes("not logged in") || normalized.includes("please run /login")) {
    return "auth_missing";
  }
  if (
    normalized.includes("failed to authenticate") ||
    normalized.includes("request not allowed") ||
    normalized.includes('"type":"forbidden"') ||
    normalized.includes(" api error: 403") ||
    normalized.includes(" forbidden")
  ) {
    return "auth_forbidden";
  }
  if (/exited with code/i.test(message)) {
    return "non_zero_exit";
  }
  return "error_during_execution";
}

function classifyClaudeResultSubtype(finalResult) {
  const joinedErrors = Array.isArray(finalResult?.errors) ? finalResult.errors.join("; ") : "";
  const fallbackMessage = `${finalResult?.result || ""}; ${joinedErrors}`.trim();
  if (finalResult?.subtype === "error_max_structured_output_retries") {
    return "schema_invalid_output";
  }
  if (finalResult?.subtype === "error_max_turns") {
    return "max_turns";
  }
  if (finalResult?.subtype === "error_max_budget_usd") {
    return "max_budget";
  }
  return classifyClaudeExecutionError(fallbackMessage);
}

async function runClaude(args) {
  const request = readJson(args.requestFile);
  const { normalizeProviderResult, normalizeIntakeInterpretationResponse, normalizeAskHumanResponse } = loadToolkitContracts(
    args.toolkitRoot,
  );

  const requestId = `${args.module}:${args.taskId}:${new Date().toISOString()}`;
  const startedAt = Date.now();
  const controller = new AbortController();
  const timeoutHandle = setTimeout(() => controller.abort(new Error("claude_provider_timeout")), args.timeoutMs);

  let finalResult = null;
  try {
    const stream = query({
      prompt: request.promptText,
      options: {
        cwd: args.taskRepo || process.cwd(),
        permissionMode: "plan",
        settingSources: ["project", "local"],
        maxTurns: 2,
        tools: [],
        systemPrompt: systemPromptForModule(args.module),
        outputFormat: {
          type: "json_schema",
          schema: schemaForModule(args.module),
        },
        ...(args.pathToClaudeCodeExecutable ? { pathToClaudeCodeExecutable: args.pathToClaudeCodeExecutable } : {}),
        abortController: controller,
      },
    });

    for await (const message of stream) {
      if (message && message.type === "result") {
        finalResult = message;
      }
    }
  } catch (error) {
    clearTimeout(timeoutHandle);
    const latencyMs = Date.now() - startedAt;
    const errorClass = error instanceof AbortError ? "timeout" : classifyClaudeExecutionError(error);
    return normalizeProviderResult(
      buildErrorResult({
        requestId,
        taskId: args.taskId,
        moduleName: args.module,
        errorClass,
        errorMessage: error?.message || String(error),
        latencyMs,
      }),
    );
  }

  clearTimeout(timeoutHandle);
  const latencyMs = Date.now() - startedAt;

  if (!finalResult) {
    return normalizeProviderResult(
      buildErrorResult({
        requestId,
        taskId: args.taskId,
        moduleName: args.module,
        errorClass: "empty_output",
        errorMessage: "Claude query finished without final result message",
        latencyMs,
      }),
    );
  }

  const tokenUsage = tokenUsageFromUsage(finalResult.usage);
  const estimatedCost = typeof finalResult.total_cost_usd === "number" ? finalResult.total_cost_usd : null;

  if (finalResult.subtype !== "success") {
    const errorClass = classifyClaudeResultSubtype(finalResult);
    return normalizeProviderResult(
      buildErrorResult({
        requestId,
        taskId: args.taskId,
        moduleName: args.module,
        errorClass,
        errorMessage: Array.isArray(finalResult.errors) ? finalResult.errors.join("; ") : finalResult.result || finalResult.subtype,
        latencyMs,
        tokenUsage,
        estimatedCost,
      }),
    );
  }

  if (finalResult.structured_output === undefined || finalResult.structured_output === null) {
    return normalizeProviderResult(
      buildErrorResult({
        requestId,
        taskId: args.taskId,
        moduleName: args.module,
        errorClass: "empty_output",
        errorMessage: "Claude result did not include structured_output",
        latencyMs,
        tokenUsage,
        estimatedCost,
      }),
    );
  }

  let normalizedResponse;
  try {
    normalizedResponse =
      args.module === "intake.interpretation"
        ? normalizeIntakeInterpretationResponse(finalResult.structured_output)
        : normalizeAskHumanResponse(finalResult.structured_output);
  } catch (error) {
    return normalizeProviderResult(
      buildErrorResult({
        requestId,
        taskId: args.taskId,
        moduleName: args.module,
        errorClass: "schema_invalid_output",
        errorMessage: error?.message || String(error),
        latencyMs,
        tokenUsage,
        estimatedCost,
      }),
    );
  }

  writeJson(args.responseFile, normalizedResponse);
  return normalizeProviderResult({
    requestId,
    taskId: args.taskId,
    module: args.module,
    provider: "claude",
    outcome: "success",
    outputText: typeof finalResult.result === "string" ? finalResult.result : null,
    structuredOutput: normalizedResponse,
    errorClass: null,
    errorMessage: null,
    latencyMs,
    tokenUsage,
    estimatedCost,
    fallbackFromProvider: null,
    meta: {},
  });
}

const args = parseArgs(process.argv);
runClaude(args)
  .then((result) => {
    console.log(JSON.stringify(result, null, 2));
  })
  .catch((error) => {
    const payload = {
      requestId: `claude_runner_internal:${new Date().toISOString()}`,
      taskId: args.taskId,
      module: args.module,
      provider: "claude",
      outcome: "error",
      outputText: null,
      structuredOutput: {},
      errorClass: "runner_internal_error",
      errorMessage: error?.message || String(error),
      latencyMs: null,
      tokenUsage: null,
      estimatedCost: null,
      fallbackFromProvider: null,
      meta: {},
    };
    console.log(JSON.stringify(payload, null, 2));
    process.exit(0);
  });
