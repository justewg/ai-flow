# Онбординг нового проекта

## Канонический путь

Для нового consumer-project точкой входа считается initializer:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/justewg/ai-flow/main/flow-init.sh) --profile acme
```

Дальше путь должен выглядеть так:

1. `flow-init.sh` materialize-ит минимальный `.flow` layout и shared toolkit.
2. `flow_configurator questionnaire` заполняет `flow.env`.
3. `onboarding_audit` проверяет repo, Project v2, secrets и runtime prerequisites.
4. `profile_init orchestrate` доводит конфигурацию до install/preflight состояния.
5. Smoke на живой карточке подтверждает `Todo -> In Progress`.

## Минимум, который должен получиться после onboarding

- `.flow/shared/scripts/run.sh` доступен как единый entrypoint;
- создан `.flow/config/flow.env`;
- проект привязан к своему `GITHUB_REPO` и `PROJECT_*`;
- daemon/watchdog используют собственные state/log directories;
- есть понимание required GitHub Actions secrets и self-hosted runner, если нужен deploy.

## Быстрые проверки

```bash
.flow/shared/scripts/run.sh onboarding_audit --profile acme
.flow/shared/scripts/run.sh profile_init preflight --profile acme
.flow/shared/scripts/run.sh status_snapshot
```

## Когда использовать quickstart, checklist и portability runbook

- Quickstart: нужен короткий end-to-end onboarding одного проекта.
- Checklist: нужен операционный пошаговый контроль внедрения.
- Portability runbook: нужен перенос current project в новый consumer-project или multi-profile контур.
