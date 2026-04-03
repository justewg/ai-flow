"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const { buildClaudeInvocationPlan } = require("../src/claude_adapter");
const { ValidationError } = require("../src/errors");

test("buildClaudeInvocationPlan returns canonical provider-json envelope", () => {
  const plan = buildClaudeInvocationPlan(
    {
      taskRepo: "/tmp/repo",
      promptFile: "/tmp/prompt.txt",
      responseFile: "/tmp/response.json",
      module: "intake.interpretation",
    },
    {
      providers: {
        default: "codex",
        intake: {
          interpretation: "claude",
          fallback: "codex",
        },
      },
    },
  );

  assert.equal(plan.provider, "claude");
  assert.equal(plan.mode, "provider-json");
  assert.equal(plan.invocation.provider, "claude");
  assert.equal(plan.invocation.transport, "runner_managed");
  assert.equal(plan.invocation.promptFile, "/tmp/prompt.txt");
  assert.equal(plan.invocation.responseFile, "/tmp/response.json");
  assert.equal(plan.invocation.taskRepo, "/tmp/repo");
});

test("buildClaudeInvocationPlan respects auto-router route", () => {
  const plan = buildClaudeInvocationPlan(
    {
      promptFile: "/tmp/prompt.txt",
      responseFile: "/tmp/response.json",
      module: "review.summary",
      preferredProvider: "auto",
      useAutoRouter: true,
    },
    {
      providers: {
        default: "codex",
        review: {
          summary: "auto",
          fallback: "codex",
        },
      },
      routing: {
        useAutoRouter: true,
      },
    },
  );

  assert.equal(plan.route.effectiveProvider, "claude");
  assert.equal(plan.telemetry.decisionReason, "auto_router_review_summary_claude");
});

test("buildClaudeInvocationPlan rejects non-claude route", () => {
  assert.throws(
    () =>
      buildClaudeInvocationPlan(
        {
          promptFile: "/tmp/prompt.txt",
          responseFile: "/tmp/response.json",
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
      ),
    ValidationError,
  );
});
