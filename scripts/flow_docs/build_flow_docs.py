#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import shutil
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPO_ROOT / "docs/flow/web-source"
CONFIG_PATH = SOURCE_ROOT / "source-map.json"
DEFAULT_OUTPUT_DIR = REPO_ROOT / ".tmp/flow-docs/site"
FLOW_DIAGRAM_DOC = REPO_ROOT / "docs/flow/issue-330-flow-diagram.md"
CHANGELOG_PATH = REPO_ROOT / "CHANGELOG.md"

FLOW_CHANGELOG_KEYWORDS = (
    "flow",
    "daemon",
    "watchdog",
    "executor",
    "project",
    "onboarding",
    "configurator",
    "migration",
    "toolkit",
    "deploy",
    "ops",
    "status",
    "telegram",
    "review",
    "bootstrap",
    "github app",
    "runtime",
    "submodule",
)


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def git_output(*args: str) -> str:
    try:
        completed = subprocess.run(
            ["git", *args],
            cwd=REPO_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return ""
    return completed.stdout.strip()


def render_sources_block(sources: list[str]) -> str:
    lines = ["## Repo sources", ""]
    for source in sources:
        lines.append(f"- `{source}`")
    return "\n".join(lines)


def extract_mermaid_blocks(markdown: str) -> list[str]:
    pattern = re.compile(r"```mermaid\n(.*?)```", re.DOTALL)
    return [match.group(1).rstrip() for match in pattern.finditer(markdown)]


def render_diagram_sections() -> str:
    diagram_doc = read_text(FLOW_DIAGRAM_DOC)
    blocks = extract_mermaid_blocks(diagram_doc)
    titles = [
        "End-to-end flow",
        "Runtime state machine",
        "Watchdog recovery path",
    ]

    sections: list[str] = []
    for index, block in enumerate(blocks):
        title = titles[index] if index < len(titles) else f"Diagram {index + 1}"
        sections.extend(
            [
                f"### {title}",
                "",
                "```mermaid",
                block,
                "```",
                "",
            ]
        )
    return "\n".join(sections).rstrip()


def render_diagram_downloads(assets: list[str]) -> str:
    lines: list[str] = []
    for asset in assets:
        target = Path("assets/diagrams") / Path(asset).name
        lines.append(f"- [`{target.name}`](../{target.as_posix()})")
    return "\n".join(lines)


def render_build_metadata() -> str:
    generated_at = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d %H:%M:%SZ")
    branch = git_output("branch", "--show-current") or "unknown"
    commit = git_output("rev-parse", "HEAD") or "unknown"
    short_commit = commit[:8] if commit != "unknown" else commit
    dirty = "yes" if git_output("status", "--short") else "no"

    return "\n".join(
        [
            f"- Собрано: `{generated_at}`",
            f"- Ветка: `{branch}`",
            f"- Commit: `{short_commit}`",
            f"- Dirty worktree во время сборки: `{dirty}`",
        ]
    )


def extract_unreleased_entries(changelog_text: str) -> list[str]:
    match = re.search(r"## \[Unreleased\](.*?)(?:\n## \[|\Z)", changelog_text, re.DOTALL)
    if not match:
        return []
    section = match.group(1)
    return re.findall(r"^- .+$", section, re.MULTILINE)


def is_flow_entry(entry: str) -> bool:
    normalized = entry.lower()
    return any(keyword in normalized for keyword in FLOW_CHANGELOG_KEYWORDS)


def render_release_notes() -> str:
    changelog_text = read_text(CHANGELOG_PATH)
    entries = [entry for entry in extract_unreleased_entries(changelog_text) if is_flow_entry(entry)]
    latest_entries = entries[:20]

    if not latest_entries:
        body = "- Подходящих flow-изменений в `CHANGELOG.md` не найдено."
    else:
        body = "\n".join(latest_entries)

    return "\n".join(
        [
            "# Последние изменения flow",
            "",
            "Этот раздел генерируется автоматически из `CHANGELOG.md` и показывает последние flow-релевантные изменения, которые уже зафиксированы в репозитории.",
            "",
            "## Unreleased delta",
            "",
            body,
            "",
            "## Release policy",
            "",
            "- Web-docs bundle пересобирается и публикуется после каждого push в `main`.",
            "- Источником release delta остается `CHANGELOG.md`.",
            "- Если изменение во flow не отражено в changelog, оно не попадет в этот раздел автоматически.",
        ]
    )


def render_source_mapping(config: dict[str, object]) -> str:
    pages = config["pages"]
    lines = [
        "# Source mapping",
        "",
        "Этот раздел генерируется из `docs/flow/web-source/source-map.json` и фиксирует, какие repo-docs участвуют в каноническом web-слое.",
        "",
        "| Web section | Канонический page source | Repo sources |",
        "| --- | --- | --- |",
    ]

    for page in pages:
        output = page["output"]
        source = page["source"]
        sources = "<br>".join(f"`{item}`" for item in page["sources"])
        lines.append(f"| `{output}` | `{source}` | {sources} |")

    lines.extend(
        [
            "",
            "## Generated sections",
            "",
            "- `reference/source-mapping.md` строится из manifest `source-map.json`.",
            "- `releases/index.md` строится из `CHANGELOG.md` с фильтрацией flow-релевантных записей.",
            "- Mermaid-диаграммы для `runtime/processes.md` извлекаются из `docs/flow/issue-330-flow-diagram.md`.",
            "- Исходные diagram-артефакты (`.mmd`, `.pdf`) копируются в `assets/diagrams/` и доступны как download attachments.",
        ]
    )
    return "\n".join(lines)


def render_sidebars(sidebar: list[dict[str, object]], depth: int = 0) -> list[str]:
    indent = "  " * depth
    lines: list[str] = []

    for item in sidebar:
        if "page" in item:
            lines.append(f"{indent}- page: {item['page']}")
            lines.append(f"{indent}  label: {item['label']}")
            continue

        lines.append(f"{indent}- group: {item['group']}")
        lines.append(f"{indent}  items:")
        lines.extend(render_sidebars(item["items"], depth + 2))

    return lines


def render_redocly_yaml() -> str:
    return "\n".join(
        [
            "apis: {}",
            "redirects: {}",
        ]
    )


def copy_diagram_assets(output_dir: Path, assets: list[str]) -> None:
    target_dir = output_dir / "assets/diagrams"
    target_dir.mkdir(parents=True, exist_ok=True)
    for asset in assets:
        source = REPO_ROOT / asset
        if not source.exists():
            raise FileNotFoundError(f"Diagram asset not found: {asset}")
        shutil.copy2(source, target_dir / source.name)


def build_pages(config: dict[str, object], output_dir: Path) -> None:
    build_metadata = render_build_metadata()
    flow_process_diagrams = render_diagram_sections()
    flow_diagram_downloads = render_diagram_downloads(config["diagram_assets"])

    replacements = {
        "{{BUILD_METADATA_LIST}}": build_metadata,
        "{{FLOW_PROCESS_DIAGRAMS}}": flow_process_diagrams,
        "{{FLOW_DIAGRAM_DOWNLOADS}}": flow_diagram_downloads,
    }

    for page in config["pages"]:
        source_path = REPO_ROOT / page["source"]
        if not source_path.exists():
            raise FileNotFoundError(f"Page source not found: {page['source']}")

        content = read_text(source_path).rstrip()
        for marker, replacement in replacements.items():
            content = content.replace(marker, replacement)

        content = f"{content}\n\n{render_sources_block(page['sources'])}\n"
        write_text(output_dir / page["output"], content)


def write_metadata(output_dir: Path) -> None:
    metadata = {
        "generated_at_utc": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "git_branch": git_output("branch", "--show-current") or "unknown",
        "git_commit": git_output("rev-parse", "HEAD") or "unknown",
        "git_commit_short": (git_output("rev-parse", "--short", "HEAD") or "unknown"),
    }
    write_text(output_dir / "build-metadata.json", json.dumps(metadata, ensure_ascii=False, indent=2) + "\n")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build Flow web docs bundle for Readocly.")
    parser.add_argument(
        "--output-dir",
        default=str(DEFAULT_OUTPUT_DIR),
        help="Directory for generated Readocly bundle.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    output_dir = Path(args.output_dir).resolve()
    config = json.loads(read_text(CONFIG_PATH))

    if output_dir.exists():
        shutil.rmtree(output_dir, ignore_errors=True)
    output_dir.mkdir(parents=True, exist_ok=True)

    build_pages(config, output_dir)
    copy_diagram_assets(output_dir, config["diagram_assets"])
    write_text(output_dir / "reference/source-mapping.md", render_source_mapping(config))
    write_text(output_dir / "releases/index.md", render_release_notes())
    write_text(output_dir / "redocly.yaml", render_redocly_yaml())
    write_text(output_dir / "sidebars.yaml", "\n".join(render_sidebars(config["sidebar"])) + "\n")
    write_metadata(output_dir)

    print(f"Built flow docs bundle: {output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
