"use strict";

const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const test = require("node:test");
const { execFileSync, spawnSync } = require("child_process");

const SHARED_DIR = path.resolve(__dirname, "..");
const SCRIPT_PATH = path.join(SHARED_DIR, "scripts", "flow_configurator.js");

function createTempRepo(t) {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "planka-flow-configurator-"));
  const repoDir = path.join(tempRoot, "acme-app");
  fs.mkdirSync(repoDir, { recursive: true });
  fs.mkdirSync(path.join(repoDir, ".flow"), { recursive: true });
  fs.symlinkSync(SHARED_DIR, path.join(repoDir, ".flow", "shared"), "dir");

  execFileSync("git", ["init"], { cwd: repoDir, stdio: "ignore" });
  execFileSync("git", ["checkout", "-b", "main"], { cwd: repoDir, stdio: "ignore" });
  execFileSync("git", ["remote", "add", "origin", "git@github.com:acme/acme-app.git"], {
    cwd: repoDir,
    stdio: "ignore",
  });

  const pemPath = path.join(tempRoot, "codex-flow.private-key.pem");
  fs.writeFileSync(pemPath, "-----BEGIN PRIVATE KEY-----\nTEST\n-----END PRIVATE KEY-----\n", "utf8");

  t.after(() => {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  });

  return {
    repoDir,
    pemPath,
    envFile: path.join(repoDir, ".flow", "config", "flow.env"),
    stateFile: path.join(repoDir, ".flow", "tmp", "wizard", "flow-configurator-state.json"),
  };
}

function runWizard(repoDir, answers, extraEnv = {}) {
  return spawnSync(process.execPath, [SCRIPT_PATH, "questionnaire", "--profile", "acme"], {
    cwd: repoDir,
    encoding: "utf8",
    env: {
      ...process.env,
      ROOT_DIR: repoDir,
      ...extraEnv,
    },
    input: `${answers.join("\n")}\n`,
  });
}

function createFakeGh(t, tempRoot, projectId) {
  const binDir = path.join(tempRoot, "bin");
  const ghPath = path.join(binDir, "gh");
  fs.mkdirSync(binDir, { recursive: true });
  fs.writeFileSync(
    ghPath,
    `#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == "project" && "$2" == "view" ]]; then
  printf '%s\\n' "${projectId}"
  exit 0
fi
exit 1
`,
    "utf8",
  );
  fs.chmodSync(ghPath, 0o755);
  t.after(() => {
    fs.rmSync(binDir, { recursive: true, force: true });
  });
  return binDir;
}

function buildInitialAnswers(pemPath) {
  return [
    "acme",
    "",
    "",
    "",
    "",
    "7",
    "PVT_kwDOACME123",
    "ghp_projectToken123",
    "super-secret-auth-1234",
    "123456",
    "654321",
    pemPath,
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "n",
    "",
    "",
    "",
    "y",
    "",
    "",
    "",
    "",
    "ops-webhook-secret-123",
    "ops-tg-secret-123",
    "12345,67890",
    "https://ops.example.com",
    "",
    "",
    "",
    "telegram-bot-token-123",
    "",
    "",
    "",
    "y",
    "1",
    "https://ops.example.com/ops/ingest/status",
    "status-secret-123",
    "",
    "",
    "1",
    "https://ops.example.com/ops/ingest/log-summary",
    "summary-secret-123",
    "",
    "",
    "",
    "",
    "y",
  ];
}

function buildCancelRerunAnswers() {
  return [
    "",
    "",
    "",
    "release",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "n",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "n",
  ];
}

test("flow_configurator materializes flow.env from questionnaire answers", (t) => {
  const sandbox = createTempRepo(t);
  const result = runWizard(sandbox.repoDir, buildInitialAnswers(sandbox.pemPath));

  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.match(result.stdout, /FLOW_CONFIGURATOR_APPLIED=1/);

  const envText = fs.readFileSync(sandbox.envFile, "utf8");
  assert.match(envText, /^PROJECT_PROFILE=acme$/m);
  assert.match(envText, /^GITHUB_REPO=acme\/acme-app$/m);
  assert.match(envText, /^PROJECT_NUMBER=7$/m);
  assert.match(envText, /^PROJECT_ID=PVT_kwDOACME123$/m);
  assert.match(envText, /^DAEMON_GH_PROJECT_TOKEN=ghp_projectToken123$/m);
  assert.match(envText, /^GH_APP_PRIVATE_KEY_PATH=.*codex-flow\.private-key\.pem$/m);
  assert.match(envText, /^OPS_BOT_PUBLIC_BASE_URL=https:\/\/ops\.example\.com$/m);
  assert.match(envText, /^OPS_REMOTE_STATUS_PUSH_ENABLED=1$/m);
  assert.match(envText, /^OPS_REMOTE_SUMMARY_PUSH_ENABLED=1$/m);

  const state = JSON.parse(fs.readFileSync(sandbox.stateFile, "utf8"));
  assert.equal(state.status, "done");
  assert.equal(state.scenario, "partial_repo");
  assert.equal(state.answers.project_profile.value, "acme");
  assert.equal(state.answers.daemon_gh_project_token.sensitive, true);
  assert.equal(state.answers.daemon_gh_project_token.reuse_policy, "sticky-secret");
  assert.equal(state.answers.github_repo.reuse_policy, "confirm-before-apply");
});

test("flow_configurator rerun does not overwrite flow.env when review is cancelled", (t) => {
  const sandbox = createTempRepo(t);
  const initial = runWizard(sandbox.repoDir, buildInitialAnswers(sandbox.pemPath));
  assert.equal(initial.status, 0, initial.stderr || initial.stdout);

  const before = fs.readFileSync(sandbox.envFile, "utf8");
  const rerun = runWizard(sandbox.repoDir, buildCancelRerunAnswers());

  assert.equal(rerun.status, 0, rerun.stderr || rerun.stdout);
  assert.match(rerun.stdout, /FLOW_CONFIGURATOR_RESULT=cancelled/);

  const after = fs.readFileSync(sandbox.envFile, "utf8");
  assert.equal(after, before);

  const state = JSON.parse(fs.readFileSync(sandbox.stateFile, "utf8"));
  assert.equal(state.status, "blocked");
  assert.equal(state.pending_overwrites[0].path, ".flow/config/flow.env");
});

test("flow_configurator derives owner, project id and auth repo defaults from updated repo answer", (t) => {
  const sandbox = createTempRepo(t);
  const fakeGhBin = createFakeGh(t, path.dirname(sandbox.pemPath), "PVT_kwDOOVERRIDE999");
  const result = runWizard(
    sandbox.repoDir,
    [
      "acme",
      "octo/new-repo",
      "",
      "",
      "",
      "42",
      "",
      "ghp_projectToken123",
      "super-secret-auth-1234",
      "123456",
      "654321",
      sandbox.pemPath,
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "n",
      "",
      "",
      "",
      "n",
      "n",
      "y",
    ],
    {
      PATH: `${fakeGhBin}${path.delimiter}${process.env.PATH || ""}`,
    },
  );

  assert.equal(result.status, 0, result.stderr || result.stdout);

  const envText = fs.readFileSync(sandbox.envFile, "utf8");
  assert.match(envText, /^GITHUB_REPO=octo\/new-repo$/m);
  assert.match(envText, /^PROJECT_OWNER=octo$/m);
  assert.match(envText, /^PROJECT_NUMBER=42$/m);
  assert.match(envText, /^PROJECT_ID=PVT_kwDOOVERRIDE999$/m);
  assert.match(envText, /^GH_APP_OWNER=octo$/m);
  assert.match(envText, /^GH_APP_REPO=new-repo$/m);
});

test("flow_configurator preserves unknown flow.env keys when applying rerun changes", (t) => {
  const sandbox = createTempRepo(t);
  const initial = runWizard(sandbox.repoDir, buildInitialAnswers(sandbox.pemPath));
  assert.equal(initial.status, 0, initial.stderr || initial.stdout);

  fs.appendFileSync(sandbox.envFile, "CUSTOM_KEEP=1\n", "utf8");
  const rerunAnswers = buildCancelRerunAnswers();
  rerunAnswers[rerunAnswers.length - 1] = "y";
  const rerun = runWizard(sandbox.repoDir, rerunAnswers);

  assert.equal(rerun.status, 0, rerun.stderr || rerun.stdout);
  assert.match(rerun.stdout, /FLOW_CONFIGURATOR_APPLIED=1/);

  const envText = fs.readFileSync(sandbox.envFile, "utf8");
  assert.match(envText, /^FLOW_HEAD_BRANCH=release$/m);
  assert.match(envText, /^CUSTOM_KEEP=1$/m);
});
