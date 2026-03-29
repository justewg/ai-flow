"use strict";

function deriveGlobalControlMode(taskStates) {
  let desiredMode = "AUTO";
  let reason = "runtime_v2_control_clear";

  for (const taskState of taskStates || []) {
    if (!taskState || typeof taskState !== "object") {
      continue;
    }
    if (taskState.budgetState === "emergency_stop") {
      return {
        mode: "EMERGENCY_STOP",
        reason: `runtime_v2_budget_emergency:${taskState.taskId}`,
        taskId: taskState.taskId,
      };
    }
    if (taskState.budgetState === "paused_budget") {
      desiredMode = "SAFE";
      reason = `runtime_v2_budget_paused:${taskState.taskId}`;
    }
  }

  return {
    mode: desiredMode,
    reason,
    taskId: null,
  };
}

module.exports = {
  deriveGlobalControlMode,
};
