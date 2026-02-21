# PL-020 - Smoke-тест автозакрытия задач

## Цель
Проверить end-to-end, что workflow `Project Auto Close Tasks` действительно переводит задачи `PL-xxx` в `Done` после merge PR в `main`.

## План прогона
1. Создать PR, где в title/body явно упомянуты `PL-019` и `PL-020`.
2. Смержить PR в `main`.
3. Проверить run в Actions:
   - workflow: `Project Auto Close Tasks`
   - статус: `success`
4. Проверить GitHub Project:
   - `PL-019` -> `Status=Done`, `Flow=Done`
   - `PL-020` -> `Status=Done`, `Flow=Done`

## Ожидаемый результат
Автоматический переход задач в `Done` без ручного `project_set_status`.
