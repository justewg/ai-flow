"use strict";

class ValidationError extends Error {
  constructor(message, details = {}) {
    super(message);
    this.name = "ValidationError";
    this.details = details;
  }
}

class ConfigError extends Error {
  constructor(message, details = {}) {
    super(message);
    this.name = "ConfigError";
    this.details = details;
  }
}

class DependencyError extends Error {
  constructor(message, details = {}) {
    super(message);
    this.name = "DependencyError";
    this.details = details;
  }
}

module.exports = {
  ValidationError,
  ConfigError,
  DependencyError,
};
