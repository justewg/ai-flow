"use strict";

const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const test = require("node:test");
const { spawnSync } = require("child_process");

const SOURCE_SCRIPTS_DIR = __dirname;

function makeExecutable(filePath) {
  fs.chmodSync(filePath, 0o755);
}

function writeExecutable(filePath, contents) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, contents, "utf8");
  makeExecutable(filePath);
}

function copyScript(fileName, destinationDir) {
  const sourcePath = path.join(SOURCE_SCRIPTS_DIR, fileName);
  const destinationPath = path.join(destinationDir, fileName);
  fs.mkdirSync(path.dirname(destinationPath), { recursive: true });
  fs.copyFileSync(sourcePath, destinationPath);
  makeExecutable(destinationPath);
}

function createSandbox(t) {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "planka-run-project-add-issue-"));
  const repoDir = path.join(tempRoot, "repo");
  const sharedScriptsDir = path.join(repoDir, ".flow", "shared", "scripts");
  const stateDir = path.join(tempRoot, "state");
  const binDir = path.join(tempRoot, "bin");

  fs.mkdirSync(sharedScriptsDir, { recursive: true });
  fs.mkdirSync(path.join(repoDir, ".flow", "config"), { recursive: true });
  fs.mkdirSync(stateDir, { recursive: true });
  fs.mkdirSync(binDir, { recursive: true });

  copyScript("run.sh", sharedScriptsDir);
  copyScript(path.join("env", "bootstrap.sh"), sharedScriptsDir);
  copyScript(path.join("env", "resolve_config.sh"), sharedScriptsDir);

  writeExecutable(
    path.join(sharedScriptsDir, "project_set_status.sh"),
    `#!/usr/bin/env bash
set -euo pipefail
printf '%s\\t%s\\t%s\\n' "$1" "$2" "$3" >> "${tempRoot}/project_set_status.log"
echo "Updated $1: Status=$2, Flow=$3"
`,
  );

  writeExecutable(
    path.join(binDir, "gh"),
    `#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "$*" >> "${tempRoot}/gh.log"

if [[ "$1" == "api" ]]; then
  exit 0
fi

if [[ "$1" == "issue" && "$2" == "edit" ]]; then
  exit 0
fi

if [[ "$1" == "project" && "$2" == "item-add" ]]; then
  exit 0
fi

echo "Unexpected gh invocation: $*" >&2
exit 1
`,
  );

  fs.writeFileSync(
    path.join(repoDir, ".flow", "config", "flow.env"),
    "GITHUB_REPO=acme/planka\n",
    "utf8",
  );
  fs.writeFileSync(path.join(stateDir, "issue_number.txt"), "406\n", "utf8");
  fs.writeFileSync(path.join(stateDir, "project_new_status.txt"), "Todo\n", "utf8");
  fs.writeFileSync(path.join(stateDir, "project_new_flow.txt"), "Ready\n", "utf8");

  t.after(() => {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  });

  return {
    binDir,
    repoDir,
    runScriptPath: path.join(sharedScriptsDir, "run.sh"),
    stateDir,
    ghLogPath: path.join(tempRoot, "gh.log"),
    statusLogPath: path.join(tempRoot, "project_set_status.log"),
  };
}

test("run.sh project_add_issue forces Backlog defaults for issue-backed items", (t) => {
  const sandbox = createSandbox(t);
  const result = spawnSync("bash", [sandbox.runScriptPath, "project_add_issue"], {
    cwd: sandbox.repoDir,
    encoding: "utf8",
    env: {
      ...process.env,
      ROOT_DIR: sandbox.repoDir,
      CODEX_STATE_DIR: sandbox.stateDir,
      PATH: `${sandbox.binDir}${path.delimiter}${process.env.PATH || ""}`,
    },
  });

  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.match(result.stdout, /Updated ISSUE-406: Status=Backlog, Flow=Backlog/);

  const statusLog = fs.readFileSync(sandbox.statusLogPath, "utf8");
  assert.match(statusLog, /^ISSUE-406\tBacklog\tBacklog$/m);
  assert.equal(statusLog.includes("Todo"), false);
  assert.equal(statusLog.includes("Ready"), false);

  const ghLog = fs.readFileSync(sandbox.ghLogPath, "utf8");
  assert.match(ghLog, /api repos\/acme\/planka\/issues\/406\/labels\?per_page=100 --jq \.\[\]\.name/);
  assert.match(ghLog, /issue edit 406 --repo acme\/planka --add-label auto:ignore/);
  assert.match(ghLog, /project item-add 2 --owner @me --url https:\/\/github\.com\/acme\/planka\/issues\/406/);
  assert.match(ghLog, /issue edit 406 --repo acme\/planka --remove-label auto:ignore/);
});
