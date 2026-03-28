"use strict";

const { ConfigError, DependencyError } = require("./errors");

function parseMongoConfig(env = process.env) {
  const uri = String(env.AIFLOW_V2_MONGODB_URI || "").trim();
  const dbName = String(env.AIFLOW_V2_MONGODB_DB || "").trim();
  const collectionPrefix = String(env.AIFLOW_V2_MONGODB_COLLECTION_PREFIX || "aiflow_v2").trim();

  if (!uri) {
    throw new ConfigError("AIFLOW_V2_MONGODB_URI is required");
  }
  if (!dbName) {
    throw new ConfigError("AIFLOW_V2_MONGODB_DB is required");
  }
  if (!collectionPrefix) {
    throw new ConfigError("AIFLOW_V2_MONGODB_COLLECTION_PREFIX must be non-empty");
  }

  return {
    uri,
    dbName,
    collectionPrefix,
  };
}

function resolveMongoDriver() {
  try {
    return require("mongodb");
  } catch (error) {
    throw new DependencyError("mongodb package is not installed", {
      hint: "Run npm install inside .flow/shared/runtime-v2 when dependency installation is available",
      cause: error && error.message ? error.message : String(error),
    });
  }
}

async function createMongoAdapter(config) {
  const { MongoClient } = resolveMongoDriver();
  const client = new MongoClient(config.uri);
  await client.connect();
  const db = client.db(config.dbName);
  const prefix = config.collectionPrefix;

  const collections = {
    tasks: db.collection(`${prefix}_tasks`),
    taskStates: db.collection(`${prefix}_task_states`),
    executions: db.collection(`${prefix}_executions`),
    events: db.collection(`${prefix}_events`),
  };

  return {
    async init() {
      await Promise.all([
        collections.tasks.createIndex({ id: 1 }, { unique: true }),
        collections.taskStates.createIndex({ taskId: 1 }, { unique: true }),
        collections.executions.createIndex({ id: 1 }, { unique: true }),
        collections.executions.createIndex({ taskId: 1, status: 1 }),
        collections.executions.createIndex({ dedupKey: 1 }),
        collections.events.createIndex({ id: 1 }, { unique: true }),
        collections.events.createIndex({ taskId: 1, createdAt: 1 }),
      ]);
    },

    async dispose() {
      await client.close();
    },

    async upsertTask(task) {
      await collections.tasks.updateOne({ id: task.id }, { $set: task }, { upsert: true });
      return task;
    },

    async getTask(taskId) {
      return collections.tasks.findOne({ id: taskId });
    },

    async listTasks() {
      return collections.tasks.find({}).sort({ id: 1 }).toArray();
    },

    async upsertTaskState(taskState) {
      await collections.taskStates.updateOne({ taskId: taskState.taskId }, { $set: taskState }, { upsert: true });
      return taskState;
    },

    async getTaskState(taskId) {
      return collections.taskStates.findOne({ taskId });
    },

    async listTaskStates() {
      return collections.taskStates.find({}).sort({ updatedAt: 1 }).toArray();
    },

    async upsertExecution(execution) {
      await collections.executions.updateOne({ id: execution.id }, { $set: execution }, { upsert: true });
      return execution;
    },

    async getExecution(executionId) {
      return collections.executions.findOne({ id: executionId });
    },

    async findExecutionByDedupKey(taskId, dedupKey) {
      return collections.executions.findOne({ taskId, dedupKey });
    },

    async listTaskExecutions(taskId) {
      return collections.executions.find({ taskId }).sort({ startedAt: 1 }).toArray();
    },

    async appendEvent(event) {
      await collections.events.insertOne(event);
      return event;
    },

    async findEventByDedupKey(taskId, dedupKey) {
      if (!dedupKey) {
        return null;
      }
      return collections.events.findOne({ taskId, dedupKey });
    },

    async listTaskEvents(taskId) {
      return collections.events.find({ taskId }).sort({ createdAt: 1 }).toArray();
    },
  };
}

module.exports = {
  parseMongoConfig,
  createMongoAdapter,
};
