# AI Flow Server Public / Secrets Layout

## Цель

Развести:

- non-secret public config
- secret material
- runtime state/logs
- sanitized diagnostics metadata

так, чтобы diagnostics path не имел read access к secrets и не мог вернуть их наружу.

## Layout

Non-secret public config:

- `/etc/ai-flow/public/platform.env`
- `/etc/ai-flow/public/projects/<profile>.env`

Secret authority:

- `/etc/ai-flow/secrets/platform/`
- `/etc/ai-flow/secrets/projects/<profile>/`

Runtime state/logs:

- `/var/sites/.ai-flow/state/<profile>/`
- `/var/sites/.ai-flow/logs/<profile>/`

Sanitized diagnostics snapshots:

- `/var/lib/ai-flow/diagnostics/<profile>/`

## Access Model

Public config:

- owner: `root:root`
- mode: `0644`
- readable для trusted host processes

Secret material:

- owner: `root:root`
- mode: `0600` files, `0700` dirs
- readable только runtime/service delivery path

Diagnostics snapshots:

- owner: `root:root`
- dir mode: `0750`
- file mode: `0640`
- writer: root-owned publisher
- reader: root-owned helper
- `aiflow` не читает snapshots напрямую

## Delivery Rules

Diagnostics layer не должен читать:

- `/etc/ai-flow/secrets/...`
- repo-local `.flow/config/flow.env`
- legacy host env files как raw diagnostic payload

Runtime должен получать secrets только из server-side authority:

- `EnvironmentFile` / service env file outside repo
- read-only bind mount exact secret file or exact secret dir

## Rotation Rules

- новые prod secrets не коммитятся;
- не синкаются обратно в локальную `.flow`;
- не возвращаются через diagnostics;
- old values считаются legacy и подлежат ротации после cutover.
