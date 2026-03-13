"use strict";

const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const test = require("node:test");
const { execFileSync, spawnSync } = require("child_process");

const SHARED_DIR = path.resolve(__dirname, "..");
const SCRIPT_PATH = path.join(SHARED_DIR, "flow-init.sh");

function createTempRepo(t) {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "planka-flow-init-"));
  const repoDir = path.join(tempRoot, "acme-app");
  fs.mkdirSync(repoDir, { recursive: true });

  execFileSync("git", ["init"], { cwd: repoDir, stdio: "ignore" });
  execFileSync("git", ["checkout", "-b", "main"], { cwd: repoDir, stdio: "ignore" });
  execFileSync("git", ["remote", "add", "origin", "git@github.com:acme/acme-app.git"], {
    cwd: repoDir,
    stdio: "ignore",
  });

  t.after(() => {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  });

  return {
    tempRoot,
    repoDir,
    envFile: path.join(repoDir, ".flow", "config", "flow.env"),
    sampleEnvFile: path.join(repoDir, ".flow", "config", "flow.sample.env"),
    stateLink: path.join(repoDir, ".flow", "state"),
    sharedDir: path.join(repoDir, ".flow", "shared"),
    commandTemplates: path.join(repoDir, "COMMAND_TEMPLATES.md"),
  };
}

function runInitializer(repoDir) {
  return spawnSync(
    "bash",
    [
      SCRIPT_PATH,
      "--target-repo",
      repoDir,
      "--profile",
      "acme",
      "--toolkit-repo",
      SHARED_DIR,
      "--toolkit-ref",
      "main",
      "--skip-questionnaire",
    ],
    {
      cwd: repoDir,
      encoding: "utf8",
      env: {
        ...process.env,
        GIT_TERMINAL_PROMPT: "0",
      },
    },
  );
}

test("flow initializer bootstraps clean git repo with toolkit and starter layout", (t) => {
  const sandbox = createTempRepo(t);
  const result = runInitializer(sandbox.repoDir);

  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.match(result.stdout, /SHARED_SUBMODULE_ACTION=added/);
  assert.match(result.stdout, /FLOW_SAMPLE_ENV_WRITTEN=/);
  assert.match(result.stdout, /ENV_TEMPLATE_WRITTEN=/);
  assert.match(result.stdout, /FLOW_INIT_NEXT_STEP=.*flow_configurator questionnaire --profile acme/);

  assert.equal(fs.existsSync(sandbox.sharedDir), true);
  assert.equal(fs.existsSync(path.join(sandbox.sharedDir, "scripts", "run.sh")), true);
  assert.equal(fs.existsSync(sandbox.sampleEnvFile), true);
  assert.equal(fs.existsSync(sandbox.envFile), true);
  assert.equal(fs.existsSync(sandbox.commandTemplates), true);
  assert.equal(fs.lstatSync(sandbox.stateLink).isSymbolicLink(), true);

  const envText = fs.readFileSync(sandbox.envFile, "utf8");
  assert.match(envText, /^PROJECT_PROFILE=acme$/m);

  const templatesText = fs.readFileSync(sandbox.commandTemplates, "utf8");
  assert.match(templatesText, /bootstrap_repo/);

  const submoduleStatus = execFileSync("git", ["submodule", "status", "--", ".flow/shared"], {
    cwd: sandbox.repoDir,
    encoding: "utf8",
  });
  assert.match(submoduleStatus, /\s\.flow\/shared$/m);
});

test("flow initializer rerun stays idempotent on already bootstrapped repo", (t) => {
  const sandbox = createTempRepo(t);
  const firstRun = runInitializer(sandbox.repoDir);
  assert.equal(firstRun.status, 0, firstRun.stderr || firstRun.stdout);

  const secondRun = runInitializer(sandbox.repoDir);
  assert.equal(secondRun.status, 0, secondRun.stderr || secondRun.stdout);
  assert.match(secondRun.stdout, /SHARED_SUBMODULE_ACTION=reused/);
  assert.match(secondRun.stdout, /ENV_TEMPLATE_EXISTS=/);
  assert.match(secondRun.stdout, /FLOW_INIT_NEXT_STEP=.*flow_configurator questionnaire --profile acme/);
});
