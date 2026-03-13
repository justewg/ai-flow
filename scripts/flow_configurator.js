#!/usr/bin/env node
"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");
const readline = require("readline");
const { spawnSync } = require("child_process");

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    printUsage();
    return 0;
  }

  const rootDir = resolveRootDir();
  const flowDir = path.join(rootDir, ".flow");
  const envFile = args.envFile || path.join(flowDir, "config", "flow.env");
  const stateFile = args.stateFile || path.join(flowDir, "tmp", "wizard", "flow-configurator-state.json");
  const profile =
    slugify(args.profile || readEnvValue(envFile, "PROJECT_PROFILE") || deriveRepoName(rootDir) || "project") || "project";

  ensureDir(path.dirname(stateFile));

  const backendRuns = [];
  const initialEnvExists = fs.existsSync(envFile);
  if (!initialEnvExists) {
    const initRun = runProfileInit(rootDir, profile, envFile);
    backendRuns.push(initRun);
    if (initRun.exitCode !== 0) {
      writeState({
        rootDir,
        stateFile,
        scenario: "partial_repo",
        status: "failed",
        currentStep: "profile_init_init",
        answers: [],
        pendingOverwrites: [],
        backendRuns,
      });
      process.stderr.write(initRun.stderr || initRun.stdout || "profile_init init failed\n");
      return initRun.exitCode || 1;
    }
  }

  const envState = loadEnvState(envFile);
  const repoFacts = collectRepoFacts(rootDir);
  const derivedProjectId = resolveProjectIdCandidate(
    rootDir,
    envState.values.get("PROJECT_OWNER") || repoFacts.repoOwner || "",
    envState.values.get("PROJECT_NUMBER") || "",
  );
  const scenario = initialEnvExists ? "rerun_reconfigure" : "partial_repo";

  const answers = [];
  const context = createContext({
    rootDir,
    profile,
    envFile,
    envState,
    repoFacts,
    derivedProjectId,
    scenario,
  });
  writeState({
    rootDir,
    stateFile,
    scenario,
    status: "questionnaire",
    currentStep: "discover",
    answers,
    pendingOverwrites: [],
    backendRuns,
  });

  const prompt = createPrompt();
  try {
    process.stdout.write(`FLOW_CONFIGURATOR_SCENARIO=${scenario}\n`);
    process.stdout.write(`FLOW_CONFIGURATOR_ENV_FILE=${envFile}\n`);
    process.stdout.write(`FLOW_CONFIGURATOR_STATE_FILE=${stateFile}\n`);
    printScenarioGuidance(scenario, envFile);

    await awaitGroup(prompt, "GitHub repo и profile", [
      question({
        key: "PROJECT_PROFILE",
        label: "PROJECT_PROFILE",
        help: "Обычно это slug имени проекта или repo, например planka.",
        required: true,
        defaultValue: (ctx) => ctx.current("PROJECT_PROFILE") || ctx.profile,
        defaultSource: (ctx) => (ctx.current("PROJECT_PROFILE") ? "flow.env" : "derived:repo-name"),
        validate: validateProfile,
        reusePolicy: "confirm-before-apply",
      }),
      question({
        key: "GITHUB_REPO",
        label: "GITHUB_REPO",
        help: "Возьми из git origin или из GitHub URL репозитория: owner/repo.",
        required: true,
        defaultValue: (ctx) => ctx.current("GITHUB_REPO") || ctx.repoFacts.repoSlug || "",
        defaultSource: (ctx) => (ctx.current("GITHUB_REPO") ? "flow.env" : "derived:git-origin"),
        validate: validateRepoSlug,
        reusePolicy: "confirm-before-apply",
      }),
      question({
        key: "FLOW_BASE_BRANCH",
        label: "FLOW_BASE_BRANCH",
        help: "Обычно это main.",
        required: true,
        defaultValue: (ctx) => ctx.current("FLOW_BASE_BRANCH") || "main",
        defaultSource: (ctx) => (ctx.current("FLOW_BASE_BRANCH") ? "flow.env" : "default:main"),
        validate: validateBranchName,
        reusePolicy: "confirm-before-apply",
      }),
      question({
        key: "FLOW_HEAD_BRANCH",
        label: "FLOW_HEAD_BRANCH",
        help: "Обычно это development.",
        required: true,
        defaultValue: (ctx) => ctx.current("FLOW_HEAD_BRANCH") || "development",
        defaultSource: (ctx) => (ctx.current("FLOW_HEAD_BRANCH") ? "flow.env" : "default:development"),
        validate: validateBranchName,
        reusePolicy: "confirm-before-apply",
      }),
    ], context, answers, stateFile, scenario, rootDir, backendRuns);

    await awaitGroup(prompt, "GitHub Project", [
      question({
        key: "PROJECT_OWNER",
        label: "PROJECT_OWNER",
        help: "Возьми из URL Project v2: /users/<owner>/projects/<number> или /orgs/<owner>/projects/<number>.",
        required: true,
        defaultValue: (ctx) => ctx.current("PROJECT_OWNER") || repoOwnerFromContext(ctx) || ctx.repoFacts.repoOwner || "",
        defaultSource: (ctx) => (ctx.current("PROJECT_OWNER") ? "flow.env" : "derived:GITHUB_REPO"),
        validate: validateProjectOwner,
        reusePolicy: "confirm-before-apply",
      }),
      question({
        key: "PROJECT_NUMBER",
        label: "PROJECT_NUMBER",
        help: "Возьми из URL Project v2 в GitHub UI.",
        required: true,
        defaultValue: (ctx) => ctx.current("PROJECT_NUMBER") || "",
        defaultSource: () => "manual:github-ui",
        validate: validatePositiveInteger,
        reusePolicy: "confirm-before-apply",
      }),
      question({
        key: "PROJECT_ID",
        label: "PROJECT_ID",
        help: "GitHub UI его не показывает. Возьми через `gh project view <number> --owner <owner> --format json --jq '.id'`.",
        required: true,
        defaultValue: (ctx) => ctx.current("PROJECT_ID") || derivedProjectIdFromContext(ctx),
        defaultSource: (ctx) => {
          if (ctx.current("PROJECT_ID")) {
            return "flow.env";
          }
          if (derivedProjectIdFromContext(ctx)) {
            return "derived:gh-project-view";
          }
          return "manual:gh-project-view";
        },
        validate: validateProjectId,
        reusePolicy: "confirm-before-apply",
      }),
    ], context, answers, stateFile, scenario, rootDir, backendRuns);

    await awaitGroup(prompt, "Project token", [
      question({
        key: "DAEMON_GH_PROJECT_TOKEN",
        label: "DAEMON_GH_PROJECT_TOKEN",
        help: "GitHub UI -> Settings -> Developer settings -> Personal access tokens -> Tokens (classic). Нужны scopes: repo, read:project, project.",
        required: true,
        sensitive: true,
        defaultValue: (ctx) => ctx.current("DAEMON_GH_PROJECT_TOKEN") || "",
        defaultSource: (ctx) => (ctx.current("DAEMON_GH_PROJECT_TOKEN") ? "flow.env" : "manual:github-ui"),
        validate: validateNonEmpty,
      }),
    ], context, answers, stateFile, scenario, rootDir, backendRuns);

    await awaitGroup(prompt, "Auth-service", [
      question({
        key: "GH_APP_INTERNAL_SECRET",
        label: "GH_APP_INTERNAL_SECRET",
        help: "Секрет, который знает daemon/watchdog и auth-service. Возьми из существующего auth-service контура или задай новый shared secret.",
        required: true,
        sensitive: true,
        defaultValue: (ctx) => ctx.current("GH_APP_INTERNAL_SECRET") || "",
        defaultSource: (ctx) => (ctx.current("GH_APP_INTERNAL_SECRET") ? "flow.env" : "manual:auth-service"),
        validate: validateInternalSecret,
      }),
      question({
        key: "GH_APP_ID",
        label: "GH_APP_ID",
        help: "GitHub App settings -> App ID.",
        required: true,
        defaultValue: (ctx) => ctx.current("GH_APP_ID") || "",
        defaultSource: (ctx) => (ctx.current("GH_APP_ID") ? "flow.env" : "manual:github-app"),
        validate: validatePositiveInteger,
      }),
      question({
        key: "GH_APP_INSTALLATION_ID",
        label: "GH_APP_INSTALLATION_ID",
        help: "GitHub App installation details или API /settings/installations.",
        required: true,
        defaultValue: (ctx) => ctx.current("GH_APP_INSTALLATION_ID") || "",
        defaultSource: (ctx) => (ctx.current("GH_APP_INSTALLATION_ID") ? "flow.env" : "manual:github-app-installation"),
        validate: validatePositiveInteger,
      }),
      question({
        key: "GH_APP_PRIVATE_KEY_PATH",
        label: "GH_APP_PRIVATE_KEY_PATH",
        help: "Локальный путь к .pem. Рекомендуемый layout: <HOME>/.secrets/gh-apps/codex-flow.private-key.pem.",
        required: true,
        defaultValue: (ctx) =>
          ctx.current("GH_APP_PRIVATE_KEY_PATH") || path.join(os.homedir(), ".secrets", "gh-apps", "codex-flow.private-key.pem"),
        defaultSource: (ctx) =>
          ctx.current("GH_APP_PRIVATE_KEY_PATH")
            ? "flow.env"
            : "default:<HOME>/.secrets/gh-apps/codex-flow.private-key.pem",
        validate: validateExistingPath,
      }),
      question({
        key: "GH_APP_OWNER",
        label: "GH_APP_OWNER",
        help: "Owner GitHub App installation, обычно совпадает с owner repo.",
        required: true,
        defaultValue: (ctx) => ctx.current("GH_APP_OWNER") || ctx.value("PROJECT_OWNER") || repoOwnerFromContext(ctx) || ctx.repoFacts.repoOwner || "",
        defaultSource: (ctx) => (ctx.current("GH_APP_OWNER") ? "flow.env" : "derived:PROJECT_OWNER"),
        validate: validateProjectOwner,
        reusePolicy: "confirm-before-apply",
      }),
      question({
        key: "GH_APP_REPO",
        label: "GH_APP_REPO",
        help: "Имя repo, к которому привязана установка GitHub App.",
        required: true,
        defaultValue: (ctx) => ctx.current("GH_APP_REPO") || repoNameFromContext(ctx) || ctx.repoFacts.repoName || "",
        defaultSource: (ctx) => (ctx.current("GH_APP_REPO") ? "flow.env" : "derived:GITHUB_REPO"),
        validate: validateRepoName,
        reusePolicy: "confirm-before-apply",
      }),
      question({
        key: "GH_APP_BIND",
        label: "GH_APP_BIND",
        help: "Локальный bind auth-service. Текущее ограничение сервиса: только 127.0.0.1.",
        required: true,
        defaultValue: (ctx) => ctx.current("GH_APP_BIND") || "127.0.0.1",
        defaultSource: (ctx) => (ctx.current("GH_APP_BIND") ? "flow.env" : "default:127.0.0.1"),
        validate: validateLocalBind,
        reusePolicy: "confirm-before-apply",
      }),
      question({
        key: "GH_APP_PORT",
        label: "GH_APP_PORT",
        help: "Локальный порт auth-service, по умолчанию 8787.",
        required: true,
        defaultValue: (ctx) => ctx.current("GH_APP_PORT") || "8787",
        defaultSource: (ctx) => (ctx.current("GH_APP_PORT") ? "flow.env" : "default:8787"),
        validate: validatePort,
        reusePolicy: "confirm-before-apply",
      }),
      question({
        key: "GH_APP_TOKEN_SKEW_SEC",
        label: "GH_APP_TOKEN_SKEW_SEC",
        help: "Запас в секундах для раннего обновления installation token. Обычно 300.",
        required: true,
        defaultValue: (ctx) => ctx.current("GH_APP_TOKEN_SKEW_SEC") || "300",
        defaultSource: (ctx) => (ctx.current("GH_APP_TOKEN_SKEW_SEC") ? "flow.env" : "default:300"),
        validate: validatePositiveInteger,
      }),
      question({
        key: "GH_APP_PM2_APP_NAME",
        label: "GH_APP_PM2_APP_NAME",
        help: "Имя PM2-процесса auth-service, если сервис отдельный для проекта.",
        required: true,
        defaultValue: (ctx) => ctx.current("GH_APP_PM2_APP_NAME") || `${ctx.value("PROJECT_PROFILE") || ctx.profile}-gh-app-auth`,
        defaultSource: (ctx) => (ctx.current("GH_APP_PM2_APP_NAME") ? "flow.env" : "derived:PROJECT_PROFILE"),
        validate: validateSimpleToken,
      }),
      question({
        key: "GH_APP_PM2_USE_DEFAULT",
        label: "GH_APP_PM2_USE_DEFAULT",
        help: "1, если допустим shared/default PM2 app name; 0, если нужен отдельный app name.",
        required: true,
        defaultValue: (ctx) => ctx.current("GH_APP_PM2_USE_DEFAULT") || "1",
        defaultSource: (ctx) => (ctx.current("GH_APP_PM2_USE_DEFAULT") ? "flow.env" : "default:1"),
        validate: validateBoolean01,
      }),
      question({
        key: "DAEMON_GH_AUTH_TIMEOUT_SEC",
        label: "DAEMON_GH_AUTH_TIMEOUT_SEC",
        help: "Таймаут запроса daemon -> auth-service. Обычно 8 секунд.",
        required: true,
        defaultValue: (ctx) => ctx.current("DAEMON_GH_AUTH_TIMEOUT_SEC") || "8",
        defaultSource: (ctx) => (ctx.current("DAEMON_GH_AUTH_TIMEOUT_SEC") ? "flow.env" : "default:8"),
        validate: validatePositiveInteger,
      }),
      question({
        key: "DAEMON_GH_AUTH_TOKEN_URL",
        label: "DAEMON_GH_AUTH_TOKEN_URL",
        help: "Опционально: явный URL /token. Если пусто, toolkit соберёт URL из GH_APP_BIND/GH_APP_PORT.",
        required: false,
        defaultValue: (ctx) => ctx.current("DAEMON_GH_AUTH_TOKEN_URL") || "",
        defaultSource: (ctx) => (ctx.current("DAEMON_GH_AUTH_TOKEN_URL") ? "flow.env" : "derived:bind+port"),
        defaultDisplay: (ctx, defaultValue) => (defaultValue ? defaultValue : `[пусто -> ${derivedAuthTokenUrlFromContext(ctx)}]`),
        validate: validateOptionalUrl,
        reusePolicy: "confirm-before-apply",
      }),
      question({
        key: "DAEMON_GH_TOKEN_FALLBACK_ENABLED",
        label: "DAEMON_GH_TOKEN_FALLBACK_ENABLED",
        help: "Аварийный PAT fallback: 1 включить, 0 выключить. Основной режим всё равно через auth-service.",
        required: true,
        defaultValue: (ctx) => ctx.current("DAEMON_GH_TOKEN_FALLBACK_ENABLED") || "0",
        defaultSource: (ctx) => (ctx.current("DAEMON_GH_TOKEN_FALLBACK_ENABLED") ? "flow.env" : "default:0"),
        validate: validateBoolean01,
      }),
    ], context, answers, stateFile, scenario, rootDir, backendRuns);

    if (truthy(context.value("DAEMON_GH_TOKEN_FALLBACK_ENABLED"))) {
      await awaitGroup(prompt, "Auth fallback PAT", [
        question({
          key: "DAEMON_GH_TOKEN",
          label: "DAEMON_GH_TOKEN",
          help: "Только аварийный fallback PAT. Оставь пустым, если fallback выключен.",
          required: true,
          sensitive: true,
          defaultValue: (ctx) => ctx.current("DAEMON_GH_TOKEN") || "",
          defaultSource: (ctx) => (ctx.current("DAEMON_GH_TOKEN") ? "flow.env" : "manual:github-ui"),
          validate: validateNonEmpty,
        }),
      ], context, answers, stateFile, scenario, rootDir, backendRuns);
    }

    if (await askConfigureGroup(prompt, "Telegram alerts", hasTelegramConfig(context))) {
      await awaitGroup(prompt, "Telegram alerts", [
        question({
          key: "DAEMON_TG_BOT_TOKEN",
          label: "DAEMON_TG_BOT_TOKEN",
          help: "BotFather -> token бота для локальных daemon/watchdog alert.",
          required: true,
          sensitive: true,
          defaultValue: (ctx) => ctx.current("DAEMON_TG_BOT_TOKEN") || "",
          defaultSource: (ctx) => (ctx.current("DAEMON_TG_BOT_TOKEN") ? "flow.env" : "manual:botfather"),
          validate: validateNonEmpty,
        }),
        question({
          key: "DAEMON_TG_CHAT_ID",
          label: "DAEMON_TG_CHAT_ID",
          help: "Получить через getUpdates/getChat. Допустимы отрицательные chat id для supergroup.",
          required: true,
          defaultValue: (ctx) => ctx.current("DAEMON_TG_CHAT_ID") || "",
          defaultSource: (ctx) => (ctx.current("DAEMON_TG_CHAT_ID") ? "flow.env" : "manual:telegram"),
          validate: validateChatId,
        }),
        question({
          key: "DAEMON_TG_REMINDER_SEC",
          label: "DAEMON_TG_REMINDER_SEC",
          help: "Период повторного напоминания в секундах. Обычно 1800.",
          required: true,
          defaultValue: (ctx) => ctx.current("DAEMON_TG_REMINDER_SEC") || "1800",
          defaultSource: (ctx) => (ctx.current("DAEMON_TG_REMINDER_SEC") ? "flow.env" : "default:1800"),
          validate: validatePositiveInteger,
        }),
        question({
          key: "DAEMON_TG_GH_DNS_REMINDER_SEC",
          label: "DAEMON_TG_GH_DNS_REMINDER_SEC",
          help: "Период напоминаний по проблемам с GitHub/DNS. Обычно 300.",
          required: true,
          defaultValue: (ctx) => ctx.current("DAEMON_TG_GH_DNS_REMINDER_SEC") || "300",
          defaultSource: (ctx) => (ctx.current("DAEMON_TG_GH_DNS_REMINDER_SEC") ? "flow.env" : "default:300"),
          validate: validatePositiveInteger,
        }),
        question({
          key: "DAEMON_TG_DIRTY_REMINDER_SEC",
          label: "DAEMON_TG_DIRTY_REMINDER_SEC",
          help: "Период напоминаний по dirty worktree. Обычно 600.",
          required: true,
          defaultValue: (ctx) => ctx.current("DAEMON_TG_DIRTY_REMINDER_SEC") || "600",
          defaultSource: (ctx) => (ctx.current("DAEMON_TG_DIRTY_REMINDER_SEC") ? "flow.env" : "default:600"),
          validate: validatePositiveInteger,
        }),
      ], context, answers, stateFile, scenario, rootDir, backendRuns);
    }

    await awaitGroup(prompt, "Launchd / daemon / watchdog", [
      question({
        key: "FLOW_LAUNCHD_NAMESPACE",
        label: "FLOW_LAUNCHD_NAMESPACE",
        help: "Префикс launchd label. Обычно com.flow.",
        required: true,
        defaultValue: (ctx) => ctx.current("FLOW_LAUNCHD_NAMESPACE") || "com.flow",
        defaultSource: (ctx) => (ctx.current("FLOW_LAUNCHD_NAMESPACE") ? "flow.env" : "default:com.flow"),
        validate: validateNamespace,
        reusePolicy: "confirm-before-apply",
      }),
      question({
        key: "WATCHDOG_DAEMON_LABEL",
        label: "WATCHDOG_DAEMON_LABEL",
        help: "Label daemon-процесса, который должен перезапускать watchdog. Обычно <namespace>.codex-daemon.<profile>.",
        required: true,
        defaultValue: (ctx) =>
          ctx.current("WATCHDOG_DAEMON_LABEL") ||
          `${ctx.value("FLOW_LAUNCHD_NAMESPACE") || "com.flow"}.codex-daemon.${ctx.value("PROJECT_PROFILE") || ctx.profile}`,
        defaultSource: (ctx) => (ctx.current("WATCHDOG_DAEMON_LABEL") ? "flow.env" : "derived:namespace+profile"),
        validate: validateLabel,
        reusePolicy: "confirm-before-apply",
      }),
      question({
        key: "WATCHDOG_DAEMON_INTERVAL_SEC",
        label: "WATCHDOG_DAEMON_INTERVAL_SEC",
        help: "Интервал watchdog в секундах. Минимум 10, стандартно 45.",
        required: true,
        defaultValue: (ctx) => ctx.current("WATCHDOG_DAEMON_INTERVAL_SEC") || "45",
        defaultSource: (ctx) => (ctx.current("WATCHDOG_DAEMON_INTERVAL_SEC") ? "flow.env" : "default:45"),
        validate: validateWatchdogInterval,
      }),
    ], context, answers, stateFile, scenario, rootDir, backendRuns);

    if (await askConfigureGroup(prompt, "Ops-бот", hasOpsBotConfig(context))) {
      await awaitGroup(prompt, "Ops-бот", [
        question({
          key: "OPS_BOT_USE_DEFAULT",
          label: "OPS_BOT_USE_DEFAULT",
          help: "1, если допустим shared/default runtime; 0, если контур кастомный.",
          required: true,
          defaultValue: (ctx) => ctx.current("OPS_BOT_USE_DEFAULT") || "1",
          defaultSource: (ctx) => (ctx.current("OPS_BOT_USE_DEFAULT") ? "flow.env" : "default:1"),
          validate: validateBoolean01,
        }),
        question({
          key: "OPS_BOT_BIND",
          label: "OPS_BOT_BIND",
          help: "Локальный bind ops-бота. Обычно 127.0.0.1.",
          required: true,
          defaultValue: (ctx) => ctx.current("OPS_BOT_BIND") || "127.0.0.1",
          defaultSource: (ctx) => (ctx.current("OPS_BOT_BIND") ? "flow.env" : "default:127.0.0.1"),
          validate: validateHostBind,
        }),
        question({
          key: "OPS_BOT_PORT",
          label: "OPS_BOT_PORT",
          help: "Локальный порт ops-бота, по умолчанию 8790.",
          required: true,
          defaultValue: (ctx) => ctx.current("OPS_BOT_PORT") || "8790",
          defaultSource: (ctx) => (ctx.current("OPS_BOT_PORT") ? "flow.env" : "default:8790"),
          validate: validatePort,
        }),
        question({
          key: "OPS_BOT_WEBHOOK_PATH",
          label: "OPS_BOT_WEBHOOK_PATH",
          help: "Локальный path для Telegram webhook. Обычно /telegram/webhook.",
          required: true,
          defaultValue: (ctx) => ctx.current("OPS_BOT_WEBHOOK_PATH") || "/telegram/webhook",
          defaultSource: (ctx) => (ctx.current("OPS_BOT_WEBHOOK_PATH") ? "flow.env" : "default:/telegram/webhook"),
          validate: validateWebhookPath,
        }),
        question({
          key: "OPS_BOT_WEBHOOK_SECRET",
          label: "OPS_BOT_WEBHOOK_SECRET",
          help: "Секрет внешнего webhook ingress/reverse proxy, если он нужен.",
          required: false,
          sensitive: true,
          defaultValue: (ctx) => ctx.current("OPS_BOT_WEBHOOK_SECRET") || "",
          defaultSource: (ctx) => (ctx.current("OPS_BOT_WEBHOOK_SECRET") ? "flow.env" : "manual:ops-bot"),
          validate: validateOptionalSecret,
        }),
        question({
          key: "OPS_BOT_TG_SECRET_TOKEN",
          label: "OPS_BOT_TG_SECRET_TOKEN",
          help: "Telegram secret token для setWebhook, если используешь webhook.",
          required: false,
          sensitive: true,
          defaultValue: (ctx) => ctx.current("OPS_BOT_TG_SECRET_TOKEN") || "",
          defaultSource: (ctx) => (ctx.current("OPS_BOT_TG_SECRET_TOKEN") ? "flow.env" : "manual:telegram"),
          validate: validateOptionalSecret,
        }),
        question({
          key: "OPS_BOT_ALLOWED_CHAT_IDS",
          label: "OPS_BOT_ALLOWED_CHAT_IDS",
          help: "Список chat id через запятую или пробел, где бот отвечает на команды.",
          required: false,
          defaultValue: (ctx) => ctx.current("OPS_BOT_ALLOWED_CHAT_IDS") || "",
          defaultSource: (ctx) => (ctx.current("OPS_BOT_ALLOWED_CHAT_IDS") ? "flow.env" : "manual:telegram"),
          validate: validateChatIdList,
        }),
        question({
          key: "OPS_BOT_PUBLIC_BASE_URL",
          label: "OPS_BOT_PUBLIC_BASE_URL",
          help: "Публичный https:// URL, если бот принимает внешний webhook или отдаёт status page.",
          required: false,
          defaultValue: (ctx) => ctx.current("OPS_BOT_PUBLIC_BASE_URL") || "",
          defaultSource: (ctx) => (ctx.current("OPS_BOT_PUBLIC_BASE_URL") ? "flow.env" : "manual:ingress"),
          validate: validateOptionalHttpsUrl,
        }),
        question({
          key: "OPS_BOT_REFRESH_SEC",
          label: "OPS_BOT_REFRESH_SEC",
          help: "Интервал cache refresh в секундах. Обычно 5.",
          required: true,
          defaultValue: (ctx) => ctx.current("OPS_BOT_REFRESH_SEC") || "5",
          defaultSource: (ctx) => (ctx.current("OPS_BOT_REFRESH_SEC") ? "flow.env" : "default:5"),
          validate: validatePositiveInteger,
        }),
        question({
          key: "OPS_BOT_CMD_TIMEOUT_MS",
          label: "OPS_BOT_CMD_TIMEOUT_MS",
          help: "Таймаут внутренних команд ops-бота в миллисекундах. Обычно 10000.",
          required: true,
          defaultValue: (ctx) => ctx.current("OPS_BOT_CMD_TIMEOUT_MS") || "10000",
          defaultSource: (ctx) => (ctx.current("OPS_BOT_CMD_TIMEOUT_MS") ? "flow.env" : "default:10000"),
          validate: validatePositiveInteger,
        }),
        question({
          key: "OPS_BOT_PM2_APP_NAME",
          label: "OPS_BOT_PM2_APP_NAME",
          help: "Имя PM2-процесса ops-бота.",
          required: true,
          defaultValue: (ctx) => ctx.current("OPS_BOT_PM2_APP_NAME") || `${ctx.value("PROJECT_PROFILE") || ctx.profile}-ops-bot`,
          defaultSource: (ctx) => (ctx.current("OPS_BOT_PM2_APP_NAME") ? "flow.env" : "derived:PROJECT_PROFILE"),
          validate: validateSimpleToken,
        }),
        question({
          key: "OPS_BOT_TG_BOT_TOKEN",
          label: "OPS_BOT_TG_BOT_TOKEN",
          help: "BotFather token для ops-бота. Если хочешь переиспользовать daemon bot, введи его явно здесь.",
          required: false,
          sensitive: true,
          defaultValue: (ctx) => ctx.current("OPS_BOT_TG_BOT_TOKEN") || "",
          defaultSource: (ctx) => (ctx.current("OPS_BOT_TG_BOT_TOKEN") ? "flow.env" : "manual:botfather"),
          validate: validateOptionalSecret,
        }),
        question({
          key: "OPS_BOT_REMOTE_STATE_DIR",
          label: "OPS_BOT_REMOTE_STATE_DIR",
          help: "Локальный каталог для remote snapshot/log-summary ingest. Обычно .flow/state/ops-bot/remote.",
          required: true,
          defaultValue: (ctx) => ctx.current("OPS_BOT_REMOTE_STATE_DIR") || ".flow/state/ops-bot/remote",
          defaultSource: (ctx) => (ctx.current("OPS_BOT_REMOTE_STATE_DIR") ? "flow.env" : "default:.flow/state/ops-bot/remote"),
          validate: validatePathLike,
        }),
        question({
          key: "OPS_BOT_REMOTE_SNAPSHOT_TTL_SEC",
          label: "OPS_BOT_REMOTE_SNAPSHOT_TTL_SEC",
          help: "TTL remote snapshot в секундах. Обычно 600.",
          required: true,
          defaultValue: (ctx) => ctx.current("OPS_BOT_REMOTE_SNAPSHOT_TTL_SEC") || "600",
          defaultSource: (ctx) => (ctx.current("OPS_BOT_REMOTE_SNAPSHOT_TTL_SEC") ? "flow.env" : "default:600"),
          validate: validatePositiveInteger,
        }),
        question({
          key: "OPS_BOT_REMOTE_SUMMARY_TTL_SEC",
          label: "OPS_BOT_REMOTE_SUMMARY_TTL_SEC",
          help: "TTL remote summary в секундах. Обычно 1200.",
          required: true,
          defaultValue: (ctx) => ctx.current("OPS_BOT_REMOTE_SUMMARY_TTL_SEC") || "1200",
          defaultSource: (ctx) => (ctx.current("OPS_BOT_REMOTE_SUMMARY_TTL_SEC") ? "flow.env" : "default:1200"),
          validate: validatePositiveInteger,
        }),
      ], context, answers, stateFile, scenario, rootDir, backendRuns);
    }

    if (await askConfigureGroup(prompt, "Remote push", hasRemotePushConfig(context))) {
      await awaitGroup(prompt, "Remote push: status snapshot", [
        question({
          key: "OPS_REMOTE_STATUS_PUSH_ENABLED",
          label: "OPS_REMOTE_STATUS_PUSH_ENABLED",
          help: "1 включает push status_snapshot на удалённый ingest endpoint, 0 отключает.",
          required: true,
          defaultValue: (ctx) => ctx.current("OPS_REMOTE_STATUS_PUSH_ENABLED") || "0",
          defaultSource: (ctx) => (ctx.current("OPS_REMOTE_STATUS_PUSH_ENABLED") ? "flow.env" : "default:0"),
          validate: validateBoolean01,
        }),
      ], context, answers, stateFile, scenario, rootDir, backendRuns);

      if (truthy(context.value("OPS_REMOTE_STATUS_PUSH_ENABLED"))) {
        await awaitGroup(prompt, "Remote push: status snapshot details", [
          question({
            key: "OPS_REMOTE_STATUS_PUSH_URL",
            label: "OPS_REMOTE_STATUS_PUSH_URL",
            help: "Публичный https:// endpoint ops ingest для status snapshot.",
            required: true,
            defaultValue: (ctx) => ctx.current("OPS_REMOTE_STATUS_PUSH_URL") || "",
            defaultSource: (ctx) => (ctx.current("OPS_REMOTE_STATUS_PUSH_URL") ? "flow.env" : "manual:remote-ingest"),
            validate: validateHttpsUrl,
          }),
          question({
            key: "OPS_REMOTE_STATUS_PUSH_SECRET",
            label: "OPS_REMOTE_STATUS_PUSH_SECRET",
            help: "Секрет заголовка X-Ops-Status-Secret для status ingest endpoint.",
            required: true,
            sensitive: true,
            defaultValue: (ctx) => ctx.current("OPS_REMOTE_STATUS_PUSH_SECRET") || "",
            defaultSource: (ctx) => (ctx.current("OPS_REMOTE_STATUS_PUSH_SECRET") ? "flow.env" : "manual:remote-ingest"),
            validate: validateNonEmpty,
          }),
          question({
            key: "OPS_REMOTE_STATUS_PUSH_TIMEOUT_SEC",
            label: "OPS_REMOTE_STATUS_PUSH_TIMEOUT_SEC",
            help: "Таймаут push в секундах. Обычно 6.",
            required: true,
            defaultValue: (ctx) => ctx.current("OPS_REMOTE_STATUS_PUSH_TIMEOUT_SEC") || "6",
            defaultSource: (ctx) => (ctx.current("OPS_REMOTE_STATUS_PUSH_TIMEOUT_SEC") ? "flow.env" : "default:6"),
            validate: validatePositiveInteger,
          }),
          question({
            key: "OPS_REMOTE_STATUS_PUSH_SOURCE",
            label: "OPS_REMOTE_STATUS_PUSH_SOURCE",
            help: "Метка источника для удалённого snapshot, обычно PROJECT_PROFILE.",
            required: true,
            defaultValue: (ctx) => ctx.current("OPS_REMOTE_STATUS_PUSH_SOURCE") || ctx.value("PROJECT_PROFILE") || ctx.profile,
            defaultSource: (ctx) => (ctx.current("OPS_REMOTE_STATUS_PUSH_SOURCE") ? "flow.env" : "derived:PROJECT_PROFILE"),
            validate: validateSimpleToken,
          }),
        ], context, answers, stateFile, scenario, rootDir, backendRuns);
      }

      await awaitGroup(prompt, "Remote push: log summary", [
        question({
          key: "OPS_REMOTE_SUMMARY_PUSH_ENABLED",
          label: "OPS_REMOTE_SUMMARY_PUSH_ENABLED",
          help: "1 включает push log_summary bundle на удалённый ingest endpoint, 0 отключает.",
          required: true,
          defaultValue: (ctx) => ctx.current("OPS_REMOTE_SUMMARY_PUSH_ENABLED") || "0",
          defaultSource: (ctx) => (ctx.current("OPS_REMOTE_SUMMARY_PUSH_ENABLED") ? "flow.env" : "default:0"),
          validate: validateBoolean01,
        }),
      ], context, answers, stateFile, scenario, rootDir, backendRuns);

      if (truthy(context.value("OPS_REMOTE_SUMMARY_PUSH_ENABLED"))) {
        await awaitGroup(prompt, "Remote push: log summary details", [
          question({
            key: "OPS_REMOTE_SUMMARY_PUSH_URL",
            label: "OPS_REMOTE_SUMMARY_PUSH_URL",
            help: "Публичный https:// endpoint ops ingest для log summary.",
            required: true,
            defaultValue: (ctx) => ctx.current("OPS_REMOTE_SUMMARY_PUSH_URL") || "",
            defaultSource: (ctx) => (ctx.current("OPS_REMOTE_SUMMARY_PUSH_URL") ? "flow.env" : "manual:remote-ingest"),
            validate: validateHttpsUrl,
          }),
          question({
            key: "OPS_REMOTE_SUMMARY_PUSH_SECRET",
            label: "OPS_REMOTE_SUMMARY_PUSH_SECRET",
            help: "Секрет заголовка для summary ingest endpoint.",
            required: true,
            sensitive: true,
            defaultValue: (ctx) => ctx.current("OPS_REMOTE_SUMMARY_PUSH_SECRET") || "",
            defaultSource: (ctx) => (ctx.current("OPS_REMOTE_SUMMARY_PUSH_SECRET") ? "flow.env" : "manual:remote-ingest"),
            validate: validateNonEmpty,
          }),
          question({
            key: "OPS_REMOTE_SUMMARY_PUSH_TIMEOUT_SEC",
            label: "OPS_REMOTE_SUMMARY_PUSH_TIMEOUT_SEC",
            help: "Таймаут push в секундах. Обычно 8.",
            required: true,
            defaultValue: (ctx) => ctx.current("OPS_REMOTE_SUMMARY_PUSH_TIMEOUT_SEC") || "8",
            defaultSource: (ctx) => (ctx.current("OPS_REMOTE_SUMMARY_PUSH_TIMEOUT_SEC") ? "flow.env" : "default:8"),
            validate: validatePositiveInteger,
          }),
          question({
            key: "OPS_REMOTE_SUMMARY_PUSH_SOURCE",
            label: "OPS_REMOTE_SUMMARY_PUSH_SOURCE",
            help: "Метка источника для удалённого summary, обычно PROJECT_PROFILE.",
            required: true,
            defaultValue: (ctx) => ctx.current("OPS_REMOTE_SUMMARY_PUSH_SOURCE") || ctx.value("PROJECT_PROFILE") || ctx.profile,
            defaultSource: (ctx) => (ctx.current("OPS_REMOTE_SUMMARY_PUSH_SOURCE") ? "flow.env" : "derived:PROJECT_PROFILE"),
            validate: validateSimpleToken,
          }),
          question({
            key: "OPS_REMOTE_SUMMARY_PUSH_HOURS",
            label: "OPS_REMOTE_SUMMARY_PUSH_HOURS",
            help: "CSV список часов для агрегированного summary, обычно 6 или 1,6,24.",
            required: true,
            defaultValue: (ctx) => ctx.current("OPS_REMOTE_SUMMARY_PUSH_HOURS") || "6",
            defaultSource: (ctx) => (ctx.current("OPS_REMOTE_SUMMARY_PUSH_HOURS") ? "flow.env" : "default:6"),
            validate: validateHoursCsv,
          }),
          question({
            key: "OPS_REMOTE_SUMMARY_PUSH_MIN_INTERVAL_SEC",
            label: "OPS_REMOTE_SUMMARY_PUSH_MIN_INTERVAL_SEC",
            help: "Минимальный интервал между summary push. Обычно 300.",
            required: true,
            defaultValue: (ctx) => ctx.current("OPS_REMOTE_SUMMARY_PUSH_MIN_INTERVAL_SEC") || "300",
            defaultSource: (ctx) => (ctx.current("OPS_REMOTE_SUMMARY_PUSH_MIN_INTERVAL_SEC") ? "flow.env" : "default:300"),
            validate: validatePositiveInteger,
          }),
        ], context, answers, stateFile, scenario, rootDir, backendRuns);
      }
    }

    validateFinalContext(context);

    const actions = planActions(envState.values, answers);
    printReview(actions, envFile);
    const applyChanges = actions.some((action) => action.action !== "keep");
    const confirm = applyChanges ? await askYesNo(prompt, "Применить изменения в .flow/config/flow.env? [y/N]: ", false) : false;

    if (!applyChanges) {
      writeState({
        rootDir,
        stateFile,
        scenario,
        status: "done",
        currentStep: "review",
        answers,
        pendingOverwrites: [],
        backendRuns,
      });
      process.stdout.write("FLOW_CONFIGURATOR_APPLIED=0\n");
      process.stdout.write("FLOW_CONFIGURATOR_CHANGES=0\n");
      process.stdout.write("FLOW_CONFIGURATOR_RESULT=no-op\n");
      return 0;
    }

    if (!confirm) {
      writeState({
        rootDir,
        stateFile,
        scenario,
        status: "blocked",
        currentStep: "review",
        answers,
        pendingOverwrites: [
          {
            path: relativePath(rootDir, envFile),
            reason: "wizard-review-not-confirmed",
            decision: "pending",
          },
        ],
        backendRuns,
      });
      process.stdout.write("FLOW_CONFIGURATOR_APPLIED=0\n");
      process.stdout.write(`FLOW_CONFIGURATOR_CHANGES=${actions.filter((item) => item.action !== "keep").length}\n`);
      process.stdout.write("FLOW_CONFIGURATOR_RESULT=cancelled\n");
      return 0;
    }

    const backupPath = applyEnvActions(rootDir, envFile, envState.lines, actions);
    writeState({
      rootDir,
      stateFile,
      scenario,
      status: "done",
      currentStep: "apply",
      answers,
      pendingOverwrites: [],
      backendRuns,
    });
    process.stdout.write("FLOW_CONFIGURATOR_APPLIED=1\n");
    process.stdout.write(`FLOW_CONFIGURATOR_CHANGES=${actions.filter((item) => item.action !== "keep").length}\n`);
    if (backupPath) {
      process.stdout.write(`FLOW_CONFIGURATOR_BACKUP=${backupPath}\n`);
    }
    process.stdout.write("FLOW_CONFIGURATOR_RESULT=updated\n");
    return 0;
  } finally {
    prompt.close();
  }
}

function parseArgs(argv) {
  const result = {
    mode: "questionnaire",
    profile: "",
    envFile: "",
    stateFile: "",
    help: false,
  };
  let index = 0;
  if (argv[index] && !argv[index].startsWith("-")) {
    result.mode = argv[index];
    index += 1;
  }
  for (; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "-h" || token === "--help" || token === "help") {
      result.help = true;
      continue;
    }
    if (token === "--profile") {
      result.profile = argv[index + 1] || "";
      index += 1;
      continue;
    }
    if (token === "--env-file") {
      result.envFile = argv[index + 1] || "";
      index += 1;
      continue;
    }
    if (token === "--state-file") {
      result.stateFile = argv[index + 1] || "";
      index += 1;
      continue;
    }
    throw new Error(`Unknown option: ${token}`);
  }
  if (result.mode !== "questionnaire") {
    throw new Error(`Unsupported mode: ${result.mode}`);
  }
  return result;
}

function printUsage() {
  process.stdout.write(`Usage: .flow/shared/scripts/flow_configurator.js [questionnaire] [options]

Options:
  --profile <name>      Имя profile для генерации defaults.
  --env-file <path>     Путь к .flow/config/flow.env.
  --state-file <path>   Путь к resume/snapshot state-файлу.
  -h, --help            Показать справку.

Examples:
  .flow/shared/scripts/run.sh flow_configurator questionnaire --profile acme
  .flow/shared/scripts/run.sh flow_configurator --profile acme
`);
}

function resolveRootDir() {
  if (process.env.ROOT_DIR) {
    return path.resolve(process.env.ROOT_DIR);
  }
  let current = process.cwd();
  while (true) {
    if (
      fs.existsSync(path.join(current, ".git")) ||
      fs.existsSync(path.join(current, ".flow", "config")) ||
      fs.existsSync(path.join(current, ".flow", "shared"))
    ) {
      return current;
    }
    const parent = path.dirname(current);
    if (parent === current) {
      break;
    }
    current = parent;
  }
  return path.resolve(__dirname, "..", "..", "..");
}

function deriveRepoName(rootDir) {
  const repoSlug = normalizeGithubRepo(runCommand("git", ["-C", rootDir, "remote", "get-url", "origin"]).stdout.trim());
  if (!repoSlug) {
    return path.basename(rootDir);
  }
  return repoSlug.split("/").slice(-1)[0];
}

function runProfileInit(rootDir, profile, envFile) {
  const profileInitPath = path.join(rootDir, ".flow", "shared", "scripts", "profile_init.sh");
  const result = runCommand(profileInitPath, ["init", "--profile", profile, "--env-file", envFile], {
    cwd: rootDir,
    env: {
      ...process.env,
      ROOT_DIR: rootDir,
    },
  });
  return {
    command: "profile_init",
    args: ["init", "--profile", profile, "--env-file", envFile],
    exitCode: result.status,
    stdout: result.stdout,
    stderr: result.stderr,
  };
}

function runCommand(command, args, options = {}) {
  const result = spawnSync(command, args, {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
    ...options,
  });
  return {
    ...result,
    stdout: result.stdout || "",
    stderr: result.stderr || "",
  };
}

function loadEnvState(envFile) {
  const lines = fs.existsSync(envFile) ? fs.readFileSync(envFile, "utf8").split(/\r?\n/) : [];
  const values = new Map();
  for (const line of lines) {
    const match = line.match(/^([A-Z0-9_]+)=(.*)$/);
    if (!match) {
      continue;
    }
    values.set(match[1], stripQuotes(match[2]));
  }
  return { lines, values };
}

function readEnvValue(envFile, key) {
  if (!fs.existsSync(envFile)) {
    return "";
  }
  const content = fs.readFileSync(envFile, "utf8");
  const lines = content.split(/\r?\n/);
  let value = "";
  for (const line of lines) {
    const match = line.match(/^([A-Z0-9_]+)=(.*)$/);
    if (match && match[1] === key) {
      value = stripQuotes(match[2]);
    }
  }
  return value;
}

function stripQuotes(value) {
  if (
    (value.startsWith("\"") && value.endsWith("\"")) ||
    (value.startsWith("'") && value.endsWith("'"))
  ) {
    return value.slice(1, -1);
  }
  return value;
}

function collectRepoFacts(rootDir) {
  const origin = runCommand("git", ["-C", rootDir, "remote", "get-url", "origin"]);
  const head = runCommand("git", ["-C", rootDir, "rev-parse", "--abbrev-ref", "HEAD"]);
  const dirty = runCommand("git", ["-C", rootDir, "status", "--short", "--untracked-files=no"]);
  const repoSlug = normalizeGithubRepo(origin.stdout.trim());
  return {
    originUrl: origin.status === 0 ? origin.stdout.trim() : "",
    repoSlug,
    repoOwner: repoSlug ? repoSlug.split("/")[0] : "",
    repoName: repoSlug ? repoSlug.split("/")[1] : "",
    headRef: head.status === 0 ? head.stdout.trim() : "",
    dirtyTracked: dirty.status === 0 ? dirty.stdout.trim().length > 0 : false,
  };
}

function normalizeGithubRepo(raw) {
  if (!raw) {
    return "";
  }
  const trimmed = raw.trim();
  const plainMatch = trimmed.match(/^([A-Za-z0-9_.-]+)\/([A-Za-z0-9_.-]+)$/);
  if (plainMatch) {
    return `${plainMatch[1]}/${plainMatch[2]}`;
  }
  const sshMatch = trimmed.match(/^git@github\.com:([^/]+)\/(.+?)(?:\.git)?$/);
  if (sshMatch) {
    return `${sshMatch[1]}/${sshMatch[2]}`;
  }
  const httpsMatch = trimmed.match(/^https:\/\/github\.com\/([^/]+)\/(.+?)(?:\.git)?$/);
  if (httpsMatch) {
    return `${httpsMatch[1]}/${httpsMatch[2]}`;
  }
  const sshUrlMatch = trimmed.match(/^ssh:\/\/git@github\.com\/([^/]+)\/(.+?)(?:\.git)?$/);
  if (sshUrlMatch) {
    return `${sshUrlMatch[1]}/${sshUrlMatch[2]}`;
  }
  return "";
}

function resolveProjectIdCandidate(rootDir, owner, projectNumber) {
  if (!owner || !projectNumber || !/^[1-9][0-9]*$/.test(projectNumber)) {
    return "";
  }
  const result = runCommand(
    "gh",
    ["project", "view", projectNumber, "--owner", owner, "--format", "json", "--jq", ".id"],
    { cwd: rootDir, timeout: 5000 },
  );
  const candidate = result.status === 0 ? result.stdout.trim() : "";
  return /^PVT_/.test(candidate) ? candidate : "";
}

function createContext({ rootDir, profile, envFile, envState, repoFacts, derivedProjectId, scenario }) {
  const resolvedValues = new Map(envState.values);
  const derivedProjectIdCache = new Map();
  return {
    rootDir,
    profile,
    envFile,
    envState,
    repoFacts,
    derivedProjectId,
    scenario,
    derivedProjectIdCache,
    current(key) {
      return envState.values.get(key) || "";
    },
    value(key) {
      return resolvedValues.get(key) || "";
    },
    setValue(key, value) {
      resolvedValues.set(key, value);
    },
  };
}

function createPrompt() {
  if (!process.stdin.isTTY) {
    const bufferedInput = fs.readFileSync(0, "utf8");
    const lines = bufferedInput.split(/\r?\n/);
    let index = 0;
    return {
      async ask(message) {
        process.stdout.write(message);
        if (index >= lines.length) {
          throw new Error("Prompt input exhausted before questionnaire completed.");
        }
        const answer = lines[index];
        index += 1;
        return answer;
      },
      close() {},
    };
  }

  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });
  return {
    async ask(message) {
      return new Promise((resolve) => {
        rl.question(message, (answer) => resolve(answer));
      });
    },
    close() {
      rl.close();
    },
  };
}

function question(config) {
  return {
    reusePolicy: config.sensitive ? "sticky-secret" : "auto-reuse",
    ...config,
  };
}

async function awaitGroup(prompt, title, questions, context, answers, stateFile, scenario, rootDir, backendRuns) {
  process.stdout.write(`\n=== ${title} ===\n`);
  process.stdout.write("Enter = принять default/сохранить текущее значение. Для очистки опционального поля введи '-'.\n");

  for (const item of questions) {
    const answer = await askQuestion(prompt, item, context);
    context.setValue(answer.key, answer.value);
    upsertAnswer(answers, answer);
  }

  writeState({
    rootDir,
    stateFile,
    scenario,
    status: "questionnaire",
    currentStep: toStepId(title),
    answers,
    pendingOverwrites: [],
    backendRuns,
  });
}

async function askConfigureGroup(prompt, title, defaultYes) {
  process.stdout.write(`\n=== ${title} ===\n`);
  const enabled = await askYesNo(
    prompt,
    `Настраивать этот контур в текущем прогоне? [${defaultYes ? "Y/n" : "y/N"}]: `,
    defaultYes,
  );
  if (!enabled) {
    process.stdout.write(`SKIP_${toStepId(title).toUpperCase()}=1\n`);
  }
  return enabled;
}

async function askQuestion(prompt, item, context) {
  const currentValue = context.current(item.key);
  const defaultValue = currentValue || String(item.defaultValue(context) || "");
  const defaultSource = currentValue ? "flow.env" : String(item.defaultSource(context) || "default");
  const defaultDisplay = renderDefaultValue(item, context, defaultValue);

  while (true) {
    process.stdout.write(`\n${item.label}\n`);
    process.stdout.write(`Источник default: ${defaultSource}\n`);
    if (context.scenario === "rerun_reconfigure" && currentValue) {
      process.stdout.write(`Поведение rerun: ${describeReusePolicy(item)}\n`);
    }
    process.stdout.write(`Где взять: ${item.help}\n`);
    if (item.sensitive) {
      process.stdout.write(
        `Default: ${defaultValue ? "[сохранить текущее/derived secret]" : "[пусто]"}\n`,
      );
    } else {
      process.stdout.write(`Default: ${defaultDisplay}\n`);
    }
    const raw = await prompt.ask("> ");
    const trimmed = raw.trim();

    let value = "";
    let source = defaultSource;
    if (trimmed === "") {
      value = defaultValue;
    } else if (trimmed === "-") {
      value = "";
      source = "manual:clear";
    } else {
      value = trimmed;
      source = "manual";
    }

    const validationError = item.validate(value, context, item);
    if (validationError) {
      process.stdout.write(`Ошибка: ${validationError}\n`);
      continue;
    }

    return {
      key: item.key,
      value,
      source,
      sensitive: Boolean(item.sensitive),
      reusePolicy: item.reusePolicy,
      status: "confirmed",
    };
  }
}

function upsertAnswer(answers, answer) {
  const index = answers.findIndex((item) => item.key === answer.key);
  if (index >= 0) {
    answers[index] = answer;
  } else {
    answers.push(answer);
  }
}

function truthy(value) {
  return /^(1|true|yes|on)$/i.test(String(value || "").trim());
}

async function askYesNo(prompt, message, defaultYes) {
  while (true) {
    const answer = (await prompt.ask(message)).trim().toLowerCase();
    if (!answer) {
      return defaultYes;
    }
    if (["y", "yes", "1"].includes(answer)) {
      return true;
    }
    if (["n", "no", "0"].includes(answer)) {
      return false;
    }
    process.stdout.write("Ответь y или n.\n");
  }
}

function validateProfile(value) {
  if (!value) {
    return "Значение обязательно.";
  }
  if (!/^[a-z0-9][a-z0-9-]*$/.test(value)) {
    return "Ожидается slug вида ^[a-z0-9][a-z0-9-]*$.";
  }
  return "";
}

function validateRepoSlug(value) {
  if (!value) {
    return "Значение обязательно.";
  }
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(value)) {
    return "Ожидается owner/repo.";
  }
  return "";
}

function validateBranchName(value) {
  if (!value) {
    return "Значение обязательно.";
  }
  if (/\s/.test(value)) {
    return "Имя ветки не должно содержать пробелы.";
  }
  return "";
}

function validateProjectOwner(value) {
  if (!value) {
    return "Значение обязательно.";
  }
  if (value === "@me") {
    return "";
  }
  if (/^\S+$/.test(value)) {
    return "";
  }
  return "Ожидается GitHub login без пробелов или @me.";
}

function validatePositiveInteger(value) {
  if (!/^[1-9][0-9]*$/.test(value)) {
    return "Ожидается целое число > 0.";
  }
  return "";
}

function validateProjectId(value) {
  if (!/^PVT_/.test(value)) {
    return "Ожидается GitHub Project node id, начинающийся с PVT_.";
  }
  return "";
}

function validateNonEmpty(value) {
  if (!value) {
    return "Значение обязательно.";
  }
  return "";
}

function validateInternalSecret(value) {
  if (!value) {
    return "Значение обязательно.";
  }
  if (value.length < 16) {
    return "Рекомендуется минимум 16 символов.";
  }
  return "";
}

function validateExistingPath(value) {
  if (!value) {
    return "Значение обязательно.";
  }
  if (!path.isAbsolute(value)) {
    return "Ожидается абсолютный путь.";
  }
  if (!fs.existsSync(value)) {
    return `Файл не найден: ${value}`;
  }
  return "";
}

function validateRepoName(value) {
  if (!value) {
    return "Значение обязательно.";
  }
  if (/^[A-Za-z0-9_.-]+$/.test(value)) {
    return "";
  }
  return "Ожидается имя repo без owner и без пробелов.";
}

function validateLocalBind(value) {
  if (value !== "127.0.0.1") {
    return "Текущее ограничение auth-service: GH_APP_BIND должен быть 127.0.0.1.";
  }
  return "";
}

function validateHostBind(value) {
  if (!value) {
    return "Значение обязательно.";
  }
  if (/^\S+$/.test(value)) {
    return "";
  }
  return "Bind не должен содержать пробелы.";
}

function validatePort(value) {
  if (!/^[0-9]+$/.test(value)) {
    return "Ожидается integer port.";
  }
  const numeric = Number(value);
  if (numeric < 1 || numeric > 65535) {
    return "Порт должен быть в диапазоне 1..65535.";
  }
  return "";
}

function validateSimpleToken(value) {
  if (!value) {
    return "Значение обязательно.";
  }
  if (/^\S+$/.test(value)) {
    return "";
  }
  return "Значение не должно содержать пробелы.";
}

function validateBoolean01(value) {
  if (value === "0" || value === "1") {
    return "";
  }
  return "Ожидается 0 или 1.";
}

function validateOptionalUrl(value) {
  if (!value) {
    return "";
  }
  return validateAnyHttpUrl(value);
}

function validateAnyHttpUrl(value) {
  try {
    const url = new URL(value);
    if (url.protocol === "http:" || url.protocol === "https:") {
      return "";
    }
  } catch (error) {
    return "Некорректный URL.";
  }
  return "Поддерживаются только http:// или https:// URL.";
}

function validateHttpsUrl(value) {
  try {
    const url = new URL(value);
    if (url.protocol === "https:") {
      return "";
    }
    return "Ожидается https:// URL.";
  } catch (error) {
    return "Некорректный URL.";
  }
}

function validateOptionalHttpsUrl(value) {
  if (!value) {
    return "";
  }
  return validateHttpsUrl(value);
}

function validateChatId(value) {
  if (!/^-?[0-9]+$/.test(value)) {
    return "Ожидается integer chat id.";
  }
  return "";
}

function validateChatIdList(value) {
  if (!value) {
    return "";
  }
  const parts = value.split(/[\s,]+/).filter(Boolean);
  if (parts.length === 0) {
    return "";
  }
  for (const item of parts) {
    if (!/^-?[0-9]+$/.test(item)) {
      return `Некорректный chat id: ${item}`;
    }
  }
  return "";
}

function validateNamespace(value) {
  if (!value) {
    return "Значение обязательно.";
  }
  if (/^[A-Za-z0-9.-]+$/.test(value)) {
    return "";
  }
  return "Namespace должен содержать только буквы, цифры, точку и дефис.";
}

function validateLabel(value) {
  if (!value) {
    return "Значение обязательно.";
  }
  if (/^[A-Za-z0-9.-]+$/.test(value)) {
    return "";
  }
  return "Label должен содержать только буквы, цифры, точку и дефис.";
}

function validateWatchdogInterval(value) {
  const error = validatePositiveInteger(value);
  if (error) {
    return error;
  }
  if (Number(value) < 10) {
    return "Интервал watchdog должен быть >= 10.";
  }
  return "";
}

function validateWebhookPath(value) {
  if (!value.startsWith("/")) {
    return "Path должен начинаться с /.";
  }
  return "";
}

function validateOptionalSecret(value) {
  if (!value) {
    return "";
  }
  return value.length >= 8 ? "" : "Рекомендуется минимум 8 символов.";
}

function validatePathLike(value) {
  if (!value) {
    return "Значение обязательно.";
  }
  if (/\s/.test(value)) {
    return "Путь не должен содержать пробелы.";
  }
  return "";
}

function validateHoursCsv(value) {
  if (!value) {
    return "Значение обязательно.";
  }
  const parts = value.split(",").map((item) => item.trim()).filter(Boolean);
  if (parts.length === 0) {
    return "Нужен хотя бы один час.";
  }
  for (const item of parts) {
    if (!/^[0-9]+$/.test(item)) {
      return `Некорректное значение часов: ${item}`;
    }
    const numeric = Number(item);
    if (numeric < 1 || numeric > 168) {
      return "Каждое значение часов должно быть в диапазоне 1..168.";
    }
  }
  return "";
}

function validateFinalContext(context) {
  if (context.value("FLOW_BASE_BRANCH") === context.value("FLOW_HEAD_BRANCH")) {
    throw new Error("FLOW_BASE_BRANCH и FLOW_HEAD_BRANCH не должны совпадать.");
  }
  if (truthy(context.value("DAEMON_GH_TOKEN_FALLBACK_ENABLED")) && !context.value("DAEMON_GH_TOKEN")) {
    throw new Error("При DAEMON_GH_TOKEN_FALLBACK_ENABLED=1 нужно заполнить DAEMON_GH_TOKEN.");
  }
}

function printScenarioGuidance(scenario, envFile) {
  if (scenario !== "rerun_reconfigure") {
    process.stdout.write("Режим initial setup: wizard соберёт значения и создаст/дополнит конфиг после финального подтверждения.\n");
    return;
  }

  process.stdout.write(`Режим rerun для ${envFile}:\n`);
  process.stdout.write("- Enter переиспользует уже подтверждённые non-secret значения.\n");
  process.stdout.write("- Секреты sticky: Enter оставляет текущее значение, новое значение нужно ввести явно.\n");
  process.stdout.write("- Изменения repo/project/runtime координат будут показаны в preview и записаны только после явного confirm.\n");
}

function repoSlugFromContext(context) {
  return context.value("GITHUB_REPO") || context.current("GITHUB_REPO") || context.repoFacts.repoSlug || "";
}

function repoOwnerFromContext(context) {
  const repoSlug = repoSlugFromContext(context);
  return repoSlug ? repoSlug.split("/")[0] : "";
}

function repoNameFromContext(context) {
  const repoSlug = repoSlugFromContext(context);
  return repoSlug ? repoSlug.split("/")[1] : "";
}

function derivedProjectIdFromContext(context) {
  const owner = context.value("PROJECT_OWNER") || repoOwnerFromContext(context);
  const projectNumber = context.value("PROJECT_NUMBER") || context.current("PROJECT_NUMBER") || "";
  if (!owner || !projectNumber) {
    return context.derivedProjectId || "";
  }

  const cacheKey = `${owner}#${projectNumber}`;
  if (context.derivedProjectIdCache.has(cacheKey)) {
    return context.derivedProjectIdCache.get(cacheKey);
  }

  const derived = resolveProjectIdCandidate(context.rootDir, owner, projectNumber) || "";
  context.derivedProjectIdCache.set(cacheKey, derived);
  const originalOwner = context.current("PROJECT_OWNER") || context.repoFacts.repoOwner || "";
  const originalProjectNumber = context.current("PROJECT_NUMBER") || "";
  if (derived) {
    return derived;
  }
  if (owner === originalOwner && projectNumber === originalProjectNumber) {
    return context.derivedProjectId || "";
  }
  return "";
}

function derivedAuthTokenUrlFromContext(context) {
  const bind = context.value("GH_APP_BIND") || context.current("GH_APP_BIND") || "127.0.0.1";
  const port = context.value("GH_APP_PORT") || context.current("GH_APP_PORT") || "8787";
  return `http://${bind}:${port}/token`;
}

function renderDefaultValue(item, context, defaultValue) {
  if (typeof item.defaultDisplay === "function") {
    return String(item.defaultDisplay(context, defaultValue) || "[пусто]");
  }
  return defaultValue || "[пусто]";
}

function describeReusePolicy(item) {
  switch (item.reusePolicy) {
    case "sticky-secret":
      return "sticky secret, заменяется только явным вводом";
    case "confirm-before-apply":
      return "значение можно переиспользовать автоматически, но любые изменения требуют явного confirm на review";
    default:
      return "значение переиспользуется автоматически, если оставить Enter";
  }
}

function hasTelegramConfig(context) {
  return Boolean(context.current("DAEMON_TG_BOT_TOKEN") || context.current("DAEMON_TG_CHAT_ID"));
}

function hasOpsBotConfig(context) {
  return Boolean(
    context.current("OPS_BOT_TG_BOT_TOKEN") ||
      context.current("OPS_BOT_ALLOWED_CHAT_IDS") ||
      context.current("OPS_BOT_PUBLIC_BASE_URL"),
  );
}

function hasRemotePushConfig(context) {
  return Boolean(
    truthy(context.current("OPS_REMOTE_STATUS_PUSH_ENABLED")) ||
      truthy(context.current("OPS_REMOTE_SUMMARY_PUSH_ENABLED")) ||
      context.current("OPS_REMOTE_STATUS_PUSH_URL") ||
      context.current("OPS_REMOTE_SUMMARY_PUSH_URL"),
  );
}

function planActions(currentValues, answers) {
  return answers
    .map((answer) => {
      const currentValue = currentValues.get(answer.key) || "";
      let action = "keep";
      if (currentValue === answer.value) {
        action = "keep";
      } else if (!currentValue && answer.value) {
        action = "create";
      } else if (currentValue && !answer.value) {
        action = "clear";
      } else if (!currentValue && !answer.value) {
        action = "keep";
      } else {
        action = "update";
      }
      return {
        ...answer,
        currentValue,
        action,
      };
    })
    .filter((item) => !(item.action === "keep" && !item.currentValue && !item.value));
}

function printReview(actions, envFile) {
  process.stdout.write(`\n=== Review: ${envFile} ===\n`);
  if (actions.length === 0 || actions.every((item) => item.action === "keep")) {
    process.stdout.write("Изменений нет. Текущая конфигурация уже совпадает с подтверждёнными ответами.\n");
    return;
  }
  const riskyChanges = actions.filter((item) => item.action !== "keep" && item.reusePolicy === "confirm-before-apply");
  if (riskyChanges.length > 0) {
    process.stdout.write("High-risk diff: меняются repo/project/runtime координаты. Перед записью будет создан backup текущего flow.env.\n");
  }
  for (const action of actions) {
    const oldValue = action.sensitive ? maskValue(action.currentValue) : action.currentValue || "[пусто]";
    const newValue = action.sensitive ? maskValue(action.value) : action.value || "[пусто]";
    const suffix = action.reusePolicy === "confirm-before-apply" ? " [confirm-before-apply]" : "";
    process.stdout.write(`${action.action.toUpperCase()} ${action.key}${suffix}: ${oldValue} -> ${newValue}\n`);
  }
}

function maskValue(value) {
  if (!value) {
    return "[пусто]";
  }
  if (value.length <= 4) {
    return "***";
  }
  return `${value.slice(0, 2)}***${value.slice(-2)}`;
}

function applyEnvActions(rootDir, envFile, originalLines, actions) {
  let lines = [...originalLines];
  let backupPath = "";
  const changedActions = actions.filter((item) => item.action !== "keep");
  if (changedActions.length === 0) {
    return backupPath;
  }
  if (fs.existsSync(envFile)) {
    const backupDir = path.join(rootDir, ".flow", "tmp", "wizard", "backups", timestampUtc().replace(/:/g, "-"));
    ensureDir(backupDir);
    backupPath = path.join(backupDir, "flow.env");
    fs.copyFileSync(envFile, backupPath);
  }
  for (const action of changedActions) {
    lines = upsertEnvLine(lines, action.key, `${action.key}=${action.value}`);
  }
  const normalized = normalizeEnvLines(lines);
  fs.writeFileSync(envFile, normalized, "utf8");
  return backupPath;
}

function upsertEnvLine(lines, key, renderedLine) {
  const nextLines = [];
  let replaced = false;
  for (const line of lines) {
    if (line.startsWith(`${key}=`)) {
      if (!replaced) {
        nextLines.push(renderedLine);
        replaced = true;
      }
      continue;
    }
    nextLines.push(line);
  }
  if (!replaced) {
    if (nextLines.length > 0 && nextLines[nextLines.length - 1] !== "") {
      nextLines.push("");
    }
    nextLines.push(renderedLine);
  }
  return nextLines;
}

function normalizeEnvLines(lines) {
  const trimmed = [...lines];
  while (trimmed.length > 0 && trimmed[trimmed.length - 1] === "") {
    trimmed.pop();
  }
  return `${trimmed.join("\n")}\n`;
}

function writeState({ rootDir, stateFile, scenario, status, currentStep, answers, pendingOverwrites, backendRuns }) {
  ensureDir(path.dirname(stateFile));
  const repoFacts = collectRepoFacts(rootDir);
  const state = {
    schema_version: 1,
    wizard: "flow-configurator",
    scenario,
    status,
    current_step: currentStep,
    repo: {
      root: rootDir,
      origin: repoFacts.originUrl,
      head_ref: repoFacts.headRef,
      dirty_tracked: repoFacts.dirtyTracked,
    },
    steps: {
      discover: { status: "completed", completed_at: timestampUtc() },
      questionnaire: { status: status === "questionnaire" ? "in_progress" : "completed", completed_at: timestampUtc() },
      review: { status: currentStep === "review" ? "in_progress" : "completed", completed_at: timestampUtc() },
      apply: { status: currentStep === "apply" || status === "done" ? "completed" : "pending", completed_at: timestampUtc() },
    },
    answers: Object.fromEntries(
      answers.map((answer) => {
        if (answer.sensitive) {
          return [
            answer.key.toLowerCase(),
            {
              masked: maskValue(answer.value),
              source: answer.source,
              status: answer.status,
              sensitive: true,
              reuse_policy: answer.reusePolicy,
            },
          ];
        }
        return [
          answer.key.toLowerCase(),
          {
            value: answer.value,
            source: answer.source,
            status: answer.status,
            reuse_policy: answer.reusePolicy,
          },
        ];
      }),
    ),
    pending_overwrites: pendingOverwrites,
    backend_runs: backendRuns.map((item) => ({
      command: item.command,
      args: item.args,
      exit_code: item.exitCode,
      summary: summarizeBackendRun(item),
    })),
  };
  fs.writeFileSync(stateFile, `${JSON.stringify(state, null, 2)}\n`, "utf8");
}

function summarizeBackendRun(item) {
  const combined = `${item.stdout || ""}\n${item.stderr || ""}`;
  const lines = combined
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .slice(0, 20);
  return {
    lines,
  };
}

function timestampUtc() {
  return new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
}

function toStepId(title) {
  return title
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
}

function relativePath(rootDir, filePath) {
  const relative = path.relative(rootDir, filePath);
  return relative && !relative.startsWith("..") ? relative : filePath;
}

function slugify(value) {
  return String(value || "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .replace(/-{2,}/g, "-");
}

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

main()
  .then((exitCode) => {
    process.exitCode = exitCode;
  })
  .catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
