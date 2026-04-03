"use strict";

const {
  normalizeTask,
  normalizeTaskState,
  normalizeExecution,
  normalizeEvent,
} = require("./schemas");
const { ValidationError } = require("./errors");

class AiFlowV2StateStore {
  constructor({ adapter }) {
    if (!adapter || typeof adapter !== "object") {
      throw new ValidationError("adapter is required");
    }
    this.adapter = adapter;
  }

  async init() {
    if (typeof this.adapter.init === "function") {
      await this.adapter.init();
    }
  }

  async putTask(taskInput) {
    const task = normalizeTask(taskInput);
    return this.adapter.upsertTask(task);
  }

  async getTask(taskId) {
    return this.adapter.getTask(taskId);
  }

  async listTasks() {
    if (typeof this.adapter.listTasks !== "function") {
      return [];
    }
    return this.adapter.listTasks();
  }

  async putTaskState(taskStateInput) {
    const taskState = normalizeTaskState(taskStateInput);
    return this.adapter.upsertTaskState(taskState);
  }

  async getTaskState(taskId) {
    return this.adapter.getTaskState(taskId);
  }

  async listTaskStates() {
    if (typeof this.adapter.listTaskStates !== "function") {
      return [];
    }
    return this.adapter.listTaskStates();
  }

  async putExecution(executionInput) {
    const execution = normalizeExecution(executionInput);
    return this.adapter.upsertExecution(execution);
  }

  async getExecution(executionId) {
    return this.adapter.getExecution(executionId);
  }

  async findExecutionByDedupKey(taskId, dedupKey) {
    if (typeof this.adapter.findExecutionByDedupKey !== "function") {
      return null;
    }
    return this.adapter.findExecutionByDedupKey(taskId, dedupKey);
  }

  async listTaskExecutions(taskId) {
    if (typeof this.adapter.listTaskExecutions !== "function") {
      return [];
    }
    return this.adapter.listTaskExecutions(taskId);
  }

  async appendEvent(eventInput) {
    const event = normalizeEvent(eventInput);
    return this.adapter.appendEvent(event);
  }

  async findEventByDedupKey(taskId, dedupKey) {
    if (typeof this.adapter.findEventByDedupKey !== "function") {
      return null;
    }
    return this.adapter.findEventByDedupKey(taskId, dedupKey);
  }

  async listTaskEvents(taskId) {
    return this.adapter.listTaskEvents(taskId);
  }

  async getTaskBundle(taskId) {
    const [task, taskState, events] = await Promise.all([
      this.getTask(taskId),
      this.getTaskState(taskId),
      this.listTaskEvents(taskId),
    ]);

    const activeExecutionId = taskState && taskState.activeExecutionId ? taskState.activeExecutionId : null;
    const activeExecution = activeExecutionId ? await this.getExecution(activeExecutionId) : null;

    return {
      task,
      taskState,
      activeExecution,
      canonicalReviewPrNumber: taskState ? taskState.canonicalReviewPrNumber : null,
      canonicalWaitCommentId: taskState ? taskState.canonicalWaitCommentId : null,
      events,
    };
  }
}

function createAiFlowV2StateStore({ adapter }) {
  return new AiFlowV2StateStore({ adapter });
}

module.exports = {
  AiFlowV2StateStore,
  createAiFlowV2StateStore,
};
