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
  collectLegacyExecutionRecords,
  projectLegacyExecutionRecord,
  syncLegacyShadowSnapshot,
} = require("./legacy_shadow");
const { evaluateLegacyPolicyGate } = require("./legacy_gate");
const { applyLegacyEventBridge } = require("./legacy_event_bridge");
const { derivePrimaryContexts } = require("./primary_context");
const {
  normalizeTask,
  normalizeTaskState,
  normalizeExecution,
  normalizeEvent,
} = require("./schemas");
const { deriveGlobalControlMode } = require("./control_policy");
const { buildInspectionSummary } = require("./inspection");
const { runRolloutValidation } = require("./validation");
const { runSingleTaskLoop } = require("./single_task_loop");
const {
  PROVIDERS,
  MODULES,
  OUTCOMES,
  normalizeProviderRequest,
  normalizeProviderResult,
} = require("./provider_contract");
const {
  normalizeProviderTelemetryRecord,
  summarizeProviderTelemetry,
} = require("./provider_telemetry");
const {
  normalizeProviderCompareConfig,
  resolveProviderCompareMode,
} = require("./provider_compare");
const {
  buildIntakeInterpretationRequest,
  normalizeIntakeInterpretationResponse,
  buildAskHumanRequest,
  normalizeAskHumanResponse,
} = require("./intake_contract");
const {
  compareInterpretationResults,
  compareAskHumanResults,
} = require("./intake_compare");
const {
  MODULE_GROUPS,
  normalizeProviderRoutingConfig,
  resolveProviderRoute,
} = require("./provider_router");
const { buildCodexInvocationPlan } = require("./codex_adapter");
const { buildClaudeInvocationPlan } = require("./claude_adapter");
const { normalizeGateOptions, evaluateProviderRolloutGate } = require("./provider_rollout_gate");
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
  collectLegacyExecutionRecords,
  projectLegacyExecutionRecord,
  syncLegacyShadowSnapshot,
  evaluateLegacyPolicyGate,
  applyLegacyEventBridge,
  derivePrimaryContexts,
  deriveGlobalControlMode,
  buildInspectionSummary,
  runRolloutValidation,
  runSingleTaskLoop,
  PROVIDERS,
  MODULES,
  OUTCOMES,
  normalizeProviderRequest,
  normalizeProviderResult,
  normalizeProviderTelemetryRecord,
  summarizeProviderTelemetry,
  normalizeProviderCompareConfig,
  resolveProviderCompareMode,
  buildIntakeInterpretationRequest,
  normalizeIntakeInterpretationResponse,
  buildAskHumanRequest,
  normalizeAskHumanResponse,
  compareInterpretationResults,
  compareAskHumanResults,
  MODULE_GROUPS,
  normalizeProviderRoutingConfig,
  resolveProviderRoute,
  buildCodexInvocationPlan,
  buildClaudeInvocationPlan,
  normalizeGateOptions,
  evaluateProviderRolloutGate,
  normalizeTask,
  normalizeTaskState,
  normalizeExecution,
  normalizeEvent,
  ValidationError,
  ConfigError,
  DependencyError,
};
