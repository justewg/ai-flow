# PLANKA

Проект цифрового коммуникационного инструмента для Андрюши.

## Документы
- `CONTEXT.md` — продуктовый источник правды.
- `TODO.md` — roadmap и статусы задач.
- `CHANGELOG.md` — журнал выполненных изменений.
- `AGENT.md` — рабочие договоренности и flow.
- `.flow/docs/gh-app-daemon-integration-plan.md` — план и runbook по включению GitHub App auth-сервиса (permissions, installation, smoke, onboarding).
- `.flow/docs/ops-bot-dashboard.md` — запуск ops-дашборда и Telegram webhook-бота (`/ops/status`, `/ops/status.json`, `/telegram/webhook/...`).

## Текущий прототип
- `prototype/web/` — MVP UI-прототип экрана 50/50 (задача `PL-003`).

## Презентация для стейкхолдеров
- `presentations/aba-v2/` — графичный deck для ABA-куратора и лиц, принимающих решение.

## Веб-нарратив + PDF экспорт
- `narrative/` — web-first лендинг в духе инженерного манифеста (задача из `docs/PRESENTATION_IMPLEMENTATION_BRIEF.md`).
  - Открыть: `narrative/index.html` в браузере.
  - PDF: использовать печать в PDF — стили в `narrative/print.css` превращают секции в страницы.
