"use strict";

function createMemoryAdapter() {
  const tasks = new Map();
  const taskStates = new Map();
  const executions = new Map();
  const events = new Map();

  return {
    async init() {
      return undefined;
    },

    async upsertTask(task) {
      tasks.set(task.id, task);
      return task;
    },

    async getTask(taskId) {
      return tasks.get(taskId) || null;
    },

    async listTasks() {
      return Array.from(tasks.values()).sort((left, right) => left.id.localeCompare(right.id));
    },

    async upsertTaskState(taskState) {
      taskStates.set(taskState.taskId, taskState);
      return taskState;
    },

    async getTaskState(taskId) {
      return taskStates.get(taskId) || null;
    },

    async listTaskStates() {
      return Array.from(taskStates.values()).sort((left, right) => String(left.updatedAt || "").localeCompare(String(right.updatedAt || "")));
    },

    async upsertExecution(execution) {
      executions.set(execution.id, execution);
      return execution;
    },

    async getExecution(executionId) {
      return executions.get(executionId) || null;
    },

    async findExecutionByDedupKey(taskId, dedupKey) {
      return (
        Array.from(executions.values()).find(
          (execution) => execution.taskId === taskId && execution.dedupKey === dedupKey,
        ) || null
      );
    },

    async listTaskExecutions(taskId) {
      return Array.from(executions.values())
        .filter((execution) => execution.taskId === taskId)
        .sort((left, right) => left.startedAt.localeCompare(right.startedAt));
    },

    async appendEvent(event) {
      events.set(event.id, event);
      return event;
    },

    async findEventByDedupKey(taskId, dedupKey) {
      if (!dedupKey) {
        return null;
      }
      return (
        Array.from(events.values()).find((event) => event.taskId === taskId && event.dedupKey === dedupKey) || null
      );
    },

    async listTaskEvents(taskId) {
      return Array.from(events.values())
        .filter((event) => event.taskId === taskId)
        .sort((left, right) => left.createdAt.localeCompare(right.createdAt));
    },
  };
}

module.exports = {
  createMemoryAdapter,
};
