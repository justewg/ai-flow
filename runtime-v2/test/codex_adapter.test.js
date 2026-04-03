"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const { buildCodexInvocationPlan } = require("../src/codex_adapter");
const { ValidationError } = require("../src/errors");

test("buildCodexInvocationPlan returns canonical full-auto codex argv", () => {
  const plan = buildCodexInvocationPlan(
    {
      taskRepo: "/tmp/repo",
      responseFile: "/tmp/last-message.txt",
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

  assert.equal(plan.provider, "codex");
  assert.equal(plan.mode, "full-auto");
  assert.deepEqual(plan.argv, [
    "codex",
    "exec",
    "-C",
    "/tmp/repo",
    "--full-auto",
    "--output-last-message",
    "/tmp/last-message.txt",
    "-",
  ]);
});

test("buildCodexInvocationPlan returns danger mode argv when bypass requested", () => {
  const plan = buildCodexInvocationPlan(
    {
      taskRepo: "/tmp/repo",
      responseFile: "/tmp/last-message.txt",
      module: "execution.micro",
      dangerouslyBypassSandbox: true,
    },
    {
      providers: {
        default: "codex",
        execution: {
          micro: "codex",
          fallback: "codex",
        },
      },
    },
  );

  assert.equal(plan.mode, "danger-full-access");
  assert.deepEqual(plan.argv.slice(0, 6), [
    "codex",
    "exec",
    "-C",
    "/tmp/repo",
    "--dangerously-bypass-approvals-and-sandbox",
    "--output-last-message",
  ]);
});

test("buildCodexInvocationPlan rejects non-codex route", () => {
  assert.throws(
    () =>
      buildCodexInvocationPlan(
        {
          taskRepo: "/tmp/repo",
          responseFile: "/tmp/last-message.txt",
          module: "review.summary",
        },
        {
          providers: {
            default: "claude",
            review: {
              summary: "claude",
              fallback: "codex",
            },
          },
        },
      ),
    ValidationError,
  );
});
