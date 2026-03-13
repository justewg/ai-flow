#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import html
import json
import posixpath
import re
import shutil
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPO_ROOT / "docs/flow/web-source"
CONFIG_PATH = SOURCE_ROOT / "source-map.json"
DEFAULT_OUTPUT_DIR = REPO_ROOT / ".tmp/flow-docs/site"
DEFAULT_STATIC_OUTPUT_DIR = REPO_ROOT / ".tmp/flow-docs/static"
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


def markdown_link_to_html(target: str) -> str:
    if target.startswith(("http://", "https://", "mailto:", "#")):
        return target
    query = ""
    anchor = ""
    if "?" in target:
        target, query = target.split("?", 1)
        query = f"?{query}"
    if "#" in target:
        target, anchor = target.split("#", 1)
        anchor = f"#{anchor}"
    normalized = posixpath.normpath(target.lstrip("/"))
    if normalized == ".":
        normalized = ""
    while normalized.startswith("../"):
        normalized = normalized[3:]
    if target.endswith(".md"):
        normalized = f"{normalized[:-3]}.html"
    if not normalized:
        return f"/{query}{anchor}" if (query or anchor) else "/"
    return f"/{normalized}{query}{anchor}"


def render_inline(markdown: str) -> str:
    code_spans: list[str] = []

    def stash_code(match: re.Match[str]) -> str:
        code_spans.append(match.group(1))
        return f"@@CODE{len(code_spans) - 1}@@"

    text = re.sub(r"`([^`]+)`", stash_code, markdown)
    text = html.escape(text)
    text = re.sub(
        r"\[([^\]]+)\]\(([^)]+)\)",
        lambda match: f'<a href="{html.escape(markdown_link_to_html(match.group(2)), quote=True)}">{match.group(1)}</a>',
        text,
    )
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"(?<!\*)\*([^*]+)\*(?!\*)", r"<em>\1</em>", text)
    for index, code in enumerate(code_spans):
        text = text.replace(f"@@CODE{index}@@", f"<code>{html.escape(code)}</code>")
    return text


def is_list_item(line: str) -> bool:
    return bool(re.match(r"^\s*(?:[-*+]|\d+\.)\s+", line))


def is_table_delimiter(line: str) -> bool:
    stripped = line.strip()
    return stripped.startswith("|") and bool(re.match(r"^\|?(?:\s*:?-{3,}:?\s*\|)+\s*$", stripped))


def is_table_row(line: str) -> bool:
    stripped = line.strip()
    return stripped.startswith("|") and stripped.count("|") >= 2


def split_table_cells(line: str) -> list[str]:
    stripped = line.strip().strip("|")
    return [cell.strip() for cell in stripped.split("|")]


def render_list(lines: list[str]) -> tuple[str, int]:
    items: list[str] = []
    ordered = bool(re.match(r"^\s*\d+\.\s+", lines[0]))
    index = 0
    while index < len(lines) and is_list_item(lines[index]):
        item = re.sub(r"^\s*(?:[-*+]|\d+\.)\s+", "", lines[index].strip())
        items.append(f"<li>{render_inline(item)}</li>")
        index += 1
    tag = "ol" if ordered else "ul"
    return f"<{tag}>\n" + "\n".join(items) + f"\n</{tag}>", index


def render_table(lines: list[str]) -> tuple[str, int]:
    header = split_table_cells(lines[0])
    index = 2
    rows: list[list[str]] = []
    while index < len(lines) and is_table_row(lines[index]):
        rows.append(split_table_cells(lines[index]))
        index += 1

    thead = "".join(f"<th>{render_inline(cell)}</th>" for cell in header)
    tbody_rows = []
    for row in rows:
        cells = "".join(f"<td>{render_inline(cell)}</td>" for cell in row)
        tbody_rows.append(f"<tr>{cells}</tr>")

    body = "\n".join(tbody_rows)
    table_html = (
        "<table>\n"
        f"<thead><tr>{thead}</tr></thead>\n"
        f"<tbody>\n{body}\n</tbody>\n"
        "</table>"
    )
    return table_html, index


def render_markdown(markdown: str) -> str:
    lines = markdown.splitlines()
    blocks: list[str] = []
    index = 0

    while index < len(lines):
        line = lines[index]
        stripped = line.strip()

        if not stripped:
            index += 1
            continue

        if stripped.startswith("```"):
            lang = stripped[3:].strip()
            index += 1
            code_lines: list[str] = []
            while index < len(lines) and not lines[index].strip().startswith("```"):
                code_lines.append(lines[index])
                index += 1
            if index < len(lines):
                index += 1
            code = html.escape("\n".join(code_lines))
            if lang == "mermaid":
                blocks.append(f'<pre class="mermaid">{code}</pre>')
            else:
                class_attr = f' class="language-{html.escape(lang, quote=True)}"' if lang else ""
                blocks.append(f"<pre><code{class_attr}>{code}</code></pre>")
            continue

        heading_match = re.match(r"^(#{1,6})\s+(.+)$", stripped)
        if heading_match:
            level = len(heading_match.group(1))
            blocks.append(f"<h{level}>{render_inline(heading_match.group(2).strip())}</h{level}>")
            index += 1
            continue

        if stripped.startswith(">"):
            quote_lines: list[str] = []
            while index < len(lines) and lines[index].strip().startswith(">"):
                quote_lines.append(re.sub(r"^\s*>\s?", "", lines[index]))
                index += 1
            blocks.append(f"<blockquote>\n{render_markdown(chr(10).join(quote_lines))}\n</blockquote>")
            continue

        if index + 1 < len(lines) and is_table_row(lines[index]) and is_table_delimiter(lines[index + 1]):
            table_html, consumed = render_table(lines[index:])
            blocks.append(table_html)
            index += consumed
            continue

        if is_list_item(line):
            list_html, consumed = render_list(lines[index:])
            blocks.append(list_html)
            index += consumed
            continue

        paragraph_lines = [stripped]
        index += 1
        while index < len(lines):
            candidate = lines[index].strip()
            if (
                not candidate
                or candidate.startswith("```")
                or candidate.startswith(">")
                or re.match(r"^(#{1,6})\s+.+$", candidate)
                or is_list_item(lines[index])
                or (index + 1 < len(lines) and is_table_row(lines[index]) and is_table_delimiter(lines[index + 1]))
            ):
                break
            paragraph_lines.append(candidate)
            index += 1
        blocks.append(f"<p>{render_inline(' '.join(paragraph_lines))}</p>")

    return "\n".join(blocks)


def flatten_sidebar(sidebar: list[dict[str, object]]) -> list[tuple[str, str, str]]:
    entries: list[tuple[str, str, str]] = []
    for item in sidebar:
        if "page" in item:
            entries.append((item["page"], item["label"], ""))
            continue
        group = item["group"]
        for page, label, _ in flatten_sidebar(item["items"]):
            entries.append((page, label, group))
    return entries


def render_static_nav(sidebar: list[dict[str, object]], current_page: str) -> str:
    lines = ['<nav class="site-nav">', '<div class="site-nav-title">Flow Docs</div>', "<ul>"]
    for item in sidebar:
        if "page" in item:
            href = markdown_link_to_html(item["page"])
            current = ' class="current"' if item["page"] == current_page else ""
            lines.append(f'<li{current}><a href="{href}">{html.escape(item["label"])}</a></li>')
            continue
        lines.append(f'<li class="group">{html.escape(item["group"])}</li>')
        for page, label, _group in flatten_sidebar(item["items"]):
            href = markdown_link_to_html(page)
            current = ' class="current"' if page == current_page else ""
            lines.append(f'<li{current}><a href="{href}">{html.escape(label)}</a></li>')
    lines.extend(["</ul>", "</nav>"])
    return "\n".join(lines)


def markdown_title(markdown: str, fallback: str) -> str:
    for line in markdown.splitlines():
        match = re.match(r"^#\s+(.+)$", line.strip())
        if match:
            return match.group(1).strip()
    return fallback


def static_css() -> str:
    return """
:root {
  color-scheme: light;
  --bg: #f5f1e8;
  --surface: rgba(255, 252, 245, 0.92);
  --surface-strong: #fffaf1;
  --ink: #1f1b17;
  --muted: #6b6258;
  --line: rgba(31, 27, 23, 0.12);
  --accent: #0d5f52;
  --accent-soft: rgba(13, 95, 82, 0.08);
  --code: #f3eee4;
  --overlay: rgba(18, 20, 24, 0.82);
  --shadow: rgba(31, 27, 23, 0.08);
}
body[data-theme="dark"] {
  color-scheme: dark;
  --bg: #121416;
  --surface: rgba(23, 28, 32, 0.9);
  --surface-strong: #1a2126;
  --ink: #f3efe7;
  --muted: #b6ada1;
  --line: rgba(243, 239, 231, 0.12);
  --accent: #72cbb9;
  --accent-soft: rgba(114, 203, 185, 0.12);
  --code: #20262c;
  --overlay: rgba(3, 6, 10, 0.9);
  --shadow: rgba(0, 0, 0, 0.3);
}
* { box-sizing: border-box; }
html { scroll-behavior: smooth; }
body {
  margin: 0;
  font-family: "Iowan Old Style", "Palatino Linotype", "Book Antiqua", Georgia, serif;
  color: var(--ink);
  background:
    radial-gradient(circle at top left, rgba(13,95,82,0.14), transparent 28%),
    radial-gradient(circle at top right, rgba(176,109,47,0.12), transparent 22%),
    linear-gradient(180deg, #f7f1e7 0%, #f1e8db 100%);
}
a { color: var(--accent); text-decoration: none; }
a:hover { text-decoration: underline; }
.layout {
  max-width: 1440px;
  margin: 0 auto;
  padding: 24px;
  display: grid;
  grid-template-columns: 300px minmax(0, 1fr);
  gap: 24px;
}
.theme-toggle {
  position: fixed;
  right: 20px;
  top: 18px;
  z-index: 40;
  border: 1px solid var(--line);
  background: var(--surface);
  color: var(--ink);
  border-radius: 999px;
  padding: 10px 14px;
  font: inherit;
  cursor: pointer;
  box-shadow: 0 16px 40px var(--shadow);
}
.site-nav, .content-shell {
  background: var(--surface);
  backdrop-filter: blur(10px);
  border: 1px solid var(--line);
  border-radius: 20px;
  box-shadow: 0 16px 40px var(--shadow);
}
.site-nav {
  position: sticky;
  top: 24px;
  align-self: start;
  padding: 20px 18px;
}
.site-nav-title {
  font-size: 1.2rem;
  font-weight: 700;
  margin-bottom: 14px;
}
.site-nav ul {
  list-style: none;
  padding: 0;
  margin: 0;
}
.site-nav li {
  margin: 0;
  color: var(--muted);
}
.site-nav li.group {
  margin-top: 16px;
  padding-top: 12px;
  border-top: 1px solid var(--line);
  font-size: 0.78rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.08em;
}
.site-nav li a {
  display: block;
  padding: 7px 10px;
  border-radius: 10px;
}
.site-nav li.current a,
.site-nav li a:hover {
  background: var(--accent-soft);
  text-decoration: none;
}
.content-shell {
  overflow: hidden;
}
.content-header {
  padding: 28px 34px 14px;
  border-bottom: 1px solid var(--line);
  background: linear-gradient(180deg, rgba(255,250,241,0.96), rgba(255,250,241,0.72));
}
.content-header .eyebrow {
  margin: 0 0 8px;
  font-size: 0.82rem;
  font-weight: 700;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: var(--muted);
}
.content-header h1 {
  margin: 0;
  font-size: clamp(2rem, 3vw, 3rem);
  line-height: 1.05;
}
.content-body {
  padding: 10px 34px 40px;
  font-size: 1.03rem;
  line-height: 1.72;
}
.content-body h1,
.content-body h2,
.content-body h3,
.content-body h4 { line-height: 1.15; margin-top: 1.6em; }
.content-body p,
.content-body ul,
.content-body ol,
.content-body blockquote,
.content-body table,
.content-body pre { margin: 1em 0; }
.content-body code {
  font-family: "SFMono-Regular", Menlo, Consolas, monospace;
  background: var(--code);
  padding: 0.15em 0.35em;
  border-radius: 6px;
  font-size: 0.94em;
}
.content-body pre {
  background: #1d232a;
  color: #f3f5f7;
  padding: 16px;
  border-radius: 16px;
  overflow-x: auto;
}
.content-body pre code {
  background: transparent;
  padding: 0;
  color: inherit;
}
.content-body blockquote {
  padding: 14px 18px;
  background: var(--accent-soft);
  border-left: 4px solid var(--accent);
  border-radius: 12px;
}
.content-body table {
  width: 100%;
  border-collapse: collapse;
  font-size: 0.96rem;
}
.content-body th,
.content-body td {
  border: 1px solid var(--line);
  padding: 10px 12px;
  text-align: left;
  vertical-align: top;
}
.content-body th {
  background: var(--surface-strong);
}
.content-body img { max-width: 100%; }
.content-body img,
.content-body .mermaid {
  cursor: zoom-in;
}
.diagram-overlay {
  position: fixed;
  inset: 0;
  z-index: 60;
  display: none;
  align-items: center;
  justify-content: center;
  padding: 28px;
  background: var(--overlay);
}
.diagram-overlay.open {
  display: flex;
}
.diagram-overlay-panel {
  max-width: min(96vw, 1400px);
  max-height: 92vh;
  overflow: auto;
  padding: 20px;
  background: var(--surface-strong);
  border-radius: 20px;
  border: 1px solid var(--line);
  box-shadow: 0 24px 60px var(--shadow);
}
.diagram-overlay-panel img,
.diagram-overlay-panel svg {
  max-width: 100%;
  height: auto;
}
@media (max-width: 980px) {
  .layout {
    grid-template-columns: 1fr;
    padding: 16px;
  }
  .site-nav {
    position: static;
  }
  .content-header,
  .content-body {
    padding-left: 22px;
    padding-right: 22px;
  }
}
""".strip()


def static_js() -> str:
    return """
(function () {
  const storageKey = 'flow-docs-theme';
  const body = document.body;

  function preferredTheme() {
    const stored = window.localStorage.getItem(storageKey);
    if (stored === 'light' || stored === 'dark') return stored;
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  }

  function applyTheme(theme) {
    body.setAttribute('data-theme', theme);
    const toggle = document.querySelector('[data-role=\"theme-toggle\"]');
    if (toggle) toggle.textContent = theme === 'dark' ? 'Light mode' : 'Dark mode';
  }

  function toggleTheme() {
    const next = body.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
    window.localStorage.setItem(storageKey, next);
    applyTheme(next);
  }

  function buildThemeToggle() {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'theme-toggle';
    button.setAttribute('data-role', 'theme-toggle');
    button.addEventListener('click', toggleTheme);
    document.body.appendChild(button);
    applyTheme(preferredTheme());
  }

  function buildOverlay() {
    const overlay = document.createElement('div');
    overlay.className = 'diagram-overlay';
    overlay.innerHTML = '<div class=\"diagram-overlay-panel\" data-role=\"overlay-panel\"></div>';
    overlay.addEventListener('click', function (event) {
      if (event.target === overlay) overlay.classList.remove('open');
    });
    document.addEventListener('keydown', function (event) {
      if (event.key === 'Escape') overlay.classList.remove('open');
    });
    document.body.appendChild(overlay);
    return overlay;
  }

  function openOverlay(overlay, node) {
    const panel = overlay.querySelector('[data-role=\"overlay-panel\"]');
    panel.innerHTML = '';
    panel.appendChild(node.cloneNode(true));
    overlay.classList.add('open');
  }

  document.addEventListener('DOMContentLoaded', function () {
    buildThemeToggle();
    const overlay = buildOverlay();

    document.addEventListener('click', function (event) {
      const image = event.target.closest('.content-body img');
      if (image) {
        event.preventDefault();
        openOverlay(overlay, image);
        return;
      }

      const mermaid = event.target.closest('.content-body .mermaid');
      if (mermaid) {
        event.preventDefault();
        openOverlay(overlay, mermaid);
      }
    });
  });
})();
""".strip()


def build_static_site(config: dict[str, object], bundle_dir: Path, static_output_dir: Path) -> None:
    if static_output_dir.exists():
        shutil.rmtree(static_output_dir, ignore_errors=True)
    static_output_dir.mkdir(parents=True, exist_ok=True)

    page_labels = {page: label for page, label, _group in flatten_sidebar(config["sidebar"])}
    for source in bundle_dir.rglob("*"):
        if source.is_dir():
            continue
        relative_path = source.relative_to(bundle_dir)
        if source.suffix.lower() == ".md":
            markdown = read_text(source)
            title = markdown_title(markdown, page_labels.get(relative_path.as_posix(), config["site"]["title"]))
            nav = render_static_nav(config["sidebar"], relative_path.as_posix())
            body = render_markdown(markdown)
            html_doc = "\n".join(
                [
                    "<!DOCTYPE html>",
                    '<html lang="ru">',
                    "<head>",
                    '  <meta charset="utf-8">',
                    '  <meta name="viewport" content="width=device-width, initial-scale=1">',
                    f"  <title>{html.escape(title)} · {html.escape(config['site']['title'])}</title>",
                    f'  <meta name="description" content="{html.escape(config["site"]["description"], quote=True)}">',
                    '  <link rel="stylesheet" href="/assets/site.css">',
                    '  <script type="module" src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs"></script>',
                    "  <script>window.addEventListener('DOMContentLoaded', function () { if (window.mermaid) { window.mermaid.initialize({ startOnLoad: true, securityLevel: 'loose' }); } });</script>",
                    '  <script defer src="/assets/site.js"></script>',
                    "</head>",
                    "<body>",
                    '  <div class="layout">',
                    f"{nav}",
                    '    <main class="content-shell">',
                    '      <header class="content-header">',
                    '        <p class="eyebrow">PLANKA Flow Docs</p>',
                    f"        <h1>{html.escape(title)}</h1>",
                    "      </header>",
                    f'      <article class="content-body">{body}</article>',
                    "    </main>",
                    "  </div>",
                    "</body>",
                    "</html>",
                ]
            )
            write_text(static_output_dir / relative_path.with_suffix(".html"), html_doc)
            continue

        target = static_output_dir / relative_path
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)

    write_text(static_output_dir / "assets/site.css", static_css() + "\n")
    write_text(static_output_dir / "assets/site.js", static_js() + "\n")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build Flow web docs bundle for Readocly.")
    parser.add_argument(
        "--output-dir",
        default=str(DEFAULT_OUTPUT_DIR),
        help="Directory for generated Readocly bundle.",
    )
    parser.add_argument(
        "--static-output-dir",
        default=str(DEFAULT_STATIC_OUTPUT_DIR),
        help="Directory for generated static HTML export.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    output_dir = Path(args.output_dir).resolve()
    static_output_dir = Path(args.static_output_dir).resolve()
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
    build_static_site(config, output_dir, static_output_dir)

    print(f"Built flow docs bundle: {output_dir}")
    print(f"Built flow docs static export: {static_output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
