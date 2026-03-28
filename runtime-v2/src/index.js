"use strict";

const { createAiFlowV2StateStore, AiFlowV2StateStore } = require("./store");
const { applyEvent } = require("./orchestrator");
const {
  buildExecutionDedupKey,
  acquireExecutionLease,
  heartbeatExecutionLease,
  releaseExecutionLease,
  evaluateExecutionStaleness,
  markExecutionStale,
} = require("./execution_policy");
const {
  normalizeRolloutMode,
  evaluateTaskBudget,
  enforceTaskBudget,
  evaluateRolloutGate,
  evaluateAutomationGate,
} = require("./budget_policy");
const { createMemoryAdapter } = require("./memory_adapter");
const { createFileAdapter } = require("./file_adapter");
const { createMongoAdapter, parseMongoConfig } = require("./mongo_adapter");
const {
  collectLegacyShadowSnapshot,
  inferTaskStateFromLegacy,
  buildSnapshotHash,
} = require("./legacy_shadow");
const {
  normalizeTask,
  normalizeTaskState,
  normalizeExecution,
  normalizeEvent,
} = require("./schemas");
const { ValidationError, ConfigError, DependencyError } = require("./errors");

module.exports = {
  AiFlowV2StateStore,
  createAiFlowV2StateStore,
  applyEvent,
  buildExecutionDedupKey,
  acquireExecutionLease,
  heartbeatExecutionLease,
  releaseExecutionLease,
  evaluateExecutionStaleness,
  markExecutionStale,
  normalizeRolloutMode,
  evaluateTaskBudget,
  enforceTaskBudget,
  evaluateRolloutGate,
  evaluateAutomationGate,
  createMemoryAdapter,
  createFileAdapter,
  createMongoAdapter,
  parseMongoConfig,
  collectLegacyShadowSnapshot,
  inferTaskStateFromLegacy,
  buildSnapshotHash,
  normalizeTask,
  normalizeTaskState,
  normalizeExecution,
  normalizeEvent,
  ValidationError,
  ConfigError,
  DependencyError,
};
