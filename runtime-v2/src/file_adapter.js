"use strict";

const fs = require("fs");
const path = require("path");

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function readJson(filePath, fallback) {
  if (!fs.existsSync(filePath)) {
    return fallback;
  }
  const raw = fs.readFileSync(filePath, "utf8").trim();
  if (!raw) {
    return fallback;
  }
  return JSON.parse(raw);
}

function writeJson(filePath, value) {
  ensureDir(path.dirname(filePath));
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function createFileAdapter({ storeDir }) {
  const baseDir = path.resolve(storeDir);
  const paths = {
    tasks: path.join(baseDir, "tasks.json"),
    taskStates: path.join(baseDir, "task_states.json"),
    executions: path.join(baseDir, "executions.json"),
    events: path.join(baseDir, "events.json"),
  };

  function readCollection(name) {
    return readJson(paths[name], {});
  }

  function writeCollection(name, value) {
    writeJson(paths[name], value);
  }

  return {
    async init() {
      ensureDir(baseDir);
      Object.keys(paths).forEach((name) => {
        if (!fs.existsSync(paths[name])) {
          writeCollection(name, {});
        }
      });
    },

    async upsertTask(task) {
      const tasks = readCollection("tasks");
      tasks[task.id] = task;
      writeCollection("tasks", tasks);
      return task;
    },

    async getTask(taskId) {
      return readCollection("tasks")[taskId] || null;
    },

    async listTasks() {
      return Object.values(readCollection("tasks")).sort((left, right) => String(left.id || "").localeCompare(String(right.id || "")));
    },

    async upsertTaskState(taskState) {
      const taskStates = readCollection("taskStates");
      taskStates[taskState.taskId] = taskState;
      writeCollection("taskStates", taskStates);
      return taskState;
    },

    async getTaskState(taskId) {
      return readCollection("taskStates")[taskId] || null;
    },

    async listTaskStates() {
      return Object.values(readCollection("taskStates")).sort((left, right) => String(left.updatedAt || "").localeCompare(String(right.updatedAt || "")));
    },

    async upsertExecution(execution) {
      const executions = readCollection("executions");
      executions[execution.id] = execution;
      writeCollection("executions", executions);
      return execution;
    },

    async getExecution(executionId) {
      return readCollection("executions")[executionId] || null;
    },

    async findExecutionByDedupKey(taskId, dedupKey) {
      const executions = Object.values(readCollection("executions"));
      return executions.find((execution) => execution.taskId === taskId && execution.dedupKey === dedupKey) || null;
    },

    async listTaskExecutions(taskId) {
      return Object.values(readCollection("executions"))
        .filter((execution) => execution.taskId === taskId)
        .sort((left, right) => String(left.startedAt || "").localeCompare(String(right.startedAt || "")));
    },

    async appendEvent(event) {
      const events = readCollection("events");
      events[event.id] = event;
      writeCollection("events", events);
      return event;
    },

    async findEventByDedupKey(taskId, dedupKey) {
      if (!dedupKey) {
        return null;
      }
      const events = Object.values(readCollection("events"));
      return events.find((event) => event.taskId === taskId && event.dedupKey === dedupKey) || null;
    },

    async listTaskEvents(taskId) {
      return Object.values(readCollection("events"))
        .filter((event) => event.taskId === taskId)
        .sort((left, right) => String(left.createdAt || "").localeCompare(String(right.createdAt || "")));
    },
  };
}

module.exports = {
  createFileAdapter,
};
