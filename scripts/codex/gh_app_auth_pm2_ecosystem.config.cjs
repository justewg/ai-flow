"use strict";

const path = require("path");

const rootDir = path.resolve(__dirname, "../..");
const pm2AppName = process.env.GH_APP_PM2_APP_NAME || "planka-gh-app-auth";
const pm2LogDir = path.join(rootDir, ".tmp", "codex", "pm2");

module.exports = {
  apps: [
    {
      name: pm2AppName,
      cwd: rootDir,
      script: "./scripts/codex/gh_app_auth_start.sh",
      interpreter: "/bin/bash",
      exec_mode: "fork",
      instances: 1,
      autorestart: true,
      max_restarts: 20,
      min_uptime: "5s",
      restart_delay: 2000,
      kill_timeout: 5000,
      watch: false,
      time: true,
      merge_logs: true,
      out_file: path.join(pm2LogDir, "gh_app_auth.out.log"),
      error_file: path.join(pm2LogDir, "gh_app_auth.err.log"),
      env: {
        NODE_ENV: "production",
      },
    },
  ],
};
