# Project Task Sync Payload

GitHub project/API для задач `PL-090..PL-096` был нестабилен в момент упаковки changeset.

Здесь лежит подготовленный payload для повторной синхронизации задач на доску `PLANKA`,
чтобы не пересобирать titles/bodies/status вручную.

Ожидаемое состояние после успешной отправки:
- `PL-090..PL-095` -> `Status=Done`, `Flow=Done`
- `PL-096` -> `Status=Backlog`, `Flow=Backlog`

Сопутствующие PR:
- `ai-flow#11`
- `planka#523`
