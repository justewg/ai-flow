"use strict";

const path = require("path");

const rootDir = path.resolve(__dirname, "../..");
const flowRootDir = path.join(rootDir, ".flow");
const pm2AppName = process.env.OPS_BOT_PM2_APP_NAME || "planka-ops-bot";
const pm2LogDir = path.join(flowRootDir, "logs", "pm2");

module.exports = {
  apps: [
    {
      name: pm2AppName,
      cwd: rootDir,
      script: "./.flow/scripts/ops_bot_start.sh",
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
      out_file: path.join(pm2LogDir, "ops_bot.out.log"),
      error_file: path.join(pm2LogDir, "ops_bot.err.log"),
      env: {
        NODE_ENV: "production",
      },
    },
  ],
};
