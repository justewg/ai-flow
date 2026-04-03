"use strict";

const { ValidationError } = require("./errors");
const { nowIso } = require("./schemas");

const ROLLOUT_MODES = new Set(["dry_run", "shadow", "single_task", "limited", "auto"]);

function normalizeRolloutMode(mode) {
  const normalized = String(mode || "dry_run").trim().toLowerCase();
  if (!ROLLOUT_MODES.has(normalized)) {
    throw new ValidationError(`unsupported rollout mode: ${normalized}`);
  }
  return normalized;
}

async function evaluateTaskBudget(store, taskId, options = {}) {
  const executions = await store.listTaskExecutions(taskId);
  const maxExecutionsPerTask = Number.isInteger(options.maxExecutionsPerTask) ? options.maxExecutionsPerTask : 3;
  const maxTokenUsagePerTask = Number.isInteger(options.maxTokenUsagePerTask) ? options.maxTokenUsagePerTask : 60000;
  const maxEstimatedCostPerTask =
    typeof options.maxEstimatedCostPerTask === "number" ? options.maxEstimatedCostPerTask : 25;

  const summary = executions.reduce(
    (acc, execution) => {
      acc.executionCount += 1;
      acc.totalTokenUsage += Number.isInteger(execution.tokenUsage) ? execution.tokenUsage : 0;
      acc.totalEstimatedCost += typeof execution.estimatedCost === "number" ? execution.estimatedCost : 0;
      return acc;
    },
    {
      executionCount: 0,
      totalTokenUsage: 0,
      totalEstimatedCost: 0,
    },
  );

  let breachReason = null;
  if (summary.executionCount > maxExecutionsPerTask) {
    breachReason = "max_executions_per_task";
  } else if (summary.totalTokenUsage > maxTokenUsagePerTask) {
    breachReason = "max_token_usage_per_task";
  } else if (summary.totalEstimatedCost > maxEstimatedCostPerTask) {
    breachReason = "max_estimated_cost_per_task";
  }

  return {
    status: breachReason ? "breach" : "ok",
    reason: breachReason || "budget_ok",
    summary,
    limits: {
      maxExecutionsPerTask,
      maxTokenUsagePerTask,
      maxEstimatedCostPerTask,
    },
  };
}

async function enforceTaskBudget(store, taskId, options = {}) {
  const budget = await evaluateTaskBudget(store, taskId, options);
  const taskState = await store.getTaskState(taskId);

  if (budget.status !== "breach") {
    return {
      status: "applied",
      reason: "budget_ok",
      budget,
      taskState,
    };
  }

  const nextBudgetState = options.emergencyOnBreach === false ? "paused_budget" : "emergency_stop";
  const nextTaskState = await store.putTaskState({
    ...(taskState || {
      taskId,
      phase: "paused",
      reason: "budget guard bootstrap",
      ownerMode: "human",
    }),
    phase: "paused",
    reason: `budget breach: ${budget.reason}`,
    budgetState: nextBudgetState,
    lockState: "frozen",
    updatedAt: nowIso(),
  });

  return {
    status: "blocked",
    reason: budget.reason,
    budget,
    taskState: nextTaskState,
  };
}

function evaluateRolloutGate({ rolloutMode, taskId, allowedTaskIds = [], expensive = false, sideEffectClass = "read_only" }) {
  const mode = normalizeRolloutMode(rolloutMode);
  const allowList = new Set(allowedTaskIds || []);
  const isExplicitlyAllowed = allowList.size === 0 ? true : allowList.has(taskId);

  switch (mode) {
    case "dry_run":
      return {
        status: "blocked",
        reason: "rollout_dry_run",
        allowExpensive: false,
        allowSideEffects: false,
      };
    case "shadow":
      return {
        status: sideEffectClass === "read_only" && !expensive ? "applied" : "blocked",
        reason: sideEffectClass === "read_only" && !expensive ? "rollout_shadow_read_only" : "rollout_shadow_blocks_side_effects",
        allowExpensive: false,
        allowSideEffects: false,
      };
    case "single_task":
      return isExplicitlyAllowed
        ? {
            status: "applied",
            reason: "rollout_single_task_allowed",
            allowExpensive: true,
            allowSideEffects: true,
          }
        : {
            status: "blocked",
            reason: "rollout_single_task_denied",
            allowExpensive: false,
            allowSideEffects: false,
          };
    case "limited":
      return isExplicitlyAllowed
        ? {
            status: "applied",
            reason: "rollout_limited_allowed",
            allowExpensive: true,
            allowSideEffects: true,
          }
        : {
            status: "blocked",
            reason: "rollout_limited_denied",
            allowExpensive: false,
            allowSideEffects: false,
          };
    case "auto":
      return {
        status: "applied",
        reason: "rollout_auto_allowed",
        allowExpensive: true,
        allowSideEffects: true,
      };
    default:
      throw new ValidationError(`unsupported rollout mode: ${mode}`);
  }
}

async function evaluateAutomationGate(store, taskId, options = {}) {
  const taskState = await store.getTaskState(taskId);
  if (taskState && ["paused_budget", "emergency_stop"].includes(taskState.budgetState)) {
    return {
      status: "blocked",
      reason: "task_budget_stopped",
      taskState,
    };
  }
  if (taskState && taskState.lockState === "frozen") {
    return {
      status: "blocked",
      reason: "task_lock_frozen",
      taskState,
    };
  }

  const rollout = evaluateRolloutGate({
    rolloutMode: options.rolloutMode,
    taskId,
    allowedTaskIds: options.allowedTaskIds,
    expensive: options.expensive,
    sideEffectClass: options.sideEffectClass,
  });
  if (rollout.status !== "applied") {
    return rollout;
  }

  const budget = await evaluateTaskBudget(store, taskId, options);
  if (budget.status === "breach") {
    return enforceTaskBudget(store, taskId, options);
  }

  return {
    status: "applied",
    reason: "automation_gate_open",
    rollout,
    budget,
    taskState,
  };
}

module.exports = {
  normalizeRolloutMode,
  evaluateTaskBudget,
  enforceTaskBudget,
  evaluateRolloutGate,
  evaluateAutomationGate,
};
