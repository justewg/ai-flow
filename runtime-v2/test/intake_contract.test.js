"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  buildIntakeInterpretationRequest,
  normalizeIntakeInterpretationResponse,
  buildAskHumanRequest,
  normalizeAskHumanResponse,
} = require("../src/intake_contract");

test("buildIntakeInterpretationRequest returns canonical request payload", () => {
  const request = buildIntakeInterpretationRequest({
    taskId: "ISSUE-622",
    issueNumber: 622,
    title: "Убрать подпись с кнопки пробела",
    body: "Короткая задача",
    replyText: "Только Android keyboard shell",
    candidateTargetFiles: ["app/src/main/res/layout/keyboard.xml"],
    repositoryContext: { repoRoot: "/tmp/repo" },
  });

  assert.equal(request.module, "intake.interpretation");
  assert.equal(request.input.taskId, "ISSUE-622");
  assert.match(request.promptText, /Candidate target files/);
  assert.match(request.promptText, /Do not classify Android kiosk/);
  assert.match(request.promptText, /\.flow\/shared/);
  assert.match(request.promptText, /Do not include \.gitmodules/);
});

test("normalizeIntakeInterpretationResponse returns canonical response payload", () => {
  const response = normalizeIntakeInterpretationResponse({
    decision: "standard",
    decisionReason: "intake_standard_android_ui",
    interpretedIntent: "Убрать подпись с кнопки пробела",
    confidence: { label: "high", score: 0.89 },
    candidateTargetFiles: ["app/src/main/res/layout/keyboard.xml"],
    rationale: ["reason=intake_standard_android_ui"],
    askHumanQuestion: null,
  });

  assert.equal(response.decision, "standard");
  assert.equal(response.confidence.label, "high");
});

test("buildAskHumanRequest returns canonical request payload", () => {
  const request = buildAskHumanRequest({
    taskId: "ISSUE-622",
    issueNumber: 622,
    kind: "QUESTION",
    contextLine: "Нужно уточнение по целевому компоненту",
    executorRemark: "1) Понял intent. 2) Не нашёл файл.",
    messageText: "Какой экран править?",
  });

  assert.equal(request.module, "intake.ask_human");
  assert.match(request.promptText, /Kind: QUESTION/);
});

test("normalizeAskHumanResponse returns canonical response payload", () => {
  const response = normalizeAskHumanResponse({
    kind: "BLOCKER",
    body: "Нужна точная привязка к компоненту.",
    expectsReply: true,
    recommendedAction: "clarify",
    options: ["Уточни keyboard component", "Продолжай"],
  });

  assert.equal(response.kind, "BLOCKER");
  assert.equal(response.recommendedAction, "clarify");
  assert.equal(response.options.length, 2);
});
