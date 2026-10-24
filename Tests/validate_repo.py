#!/usr/bin/env python3
"""Validate documentation links and release-facing repository structure."""

from __future__ import annotations

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def check_required_files() -> int:
    required = [
        "README.md",
        "README.en.md",
        "README.ar.md",
        "Package.swift",
        "LICENSE",
        "Sources/MenuMonitorApp/MenuMonitorApp.swift",
        "Sources/MenuMonitorCore/Metrics/MetricModels.swift",
        "Tests/MenuMonitorCoreTests/MetricStateTests.swift",
        "docs/images/hero-menu-monitor.jpg",
        "docs/images/live-panel.jpg",
        "docs/images/settings.jpg",
    ]
    missing = [path for path in required if not (ROOT / path).is_file()]
    if missing:
        raise AssertionError("missing required files: " + ", ".join(missing))
    return len(required)


def check_links() -> int:
    checked = 0
    missing: list[str] = []
    for path in ROOT.rglob("*"):
        if not path.is_file() or path.suffix.lower() not in {".md", ".txt", ".html"}:
            continue
        text = path.read_text(encoding="utf-8-sig", errors="replace")
        targets = re.findall(r"\[[^\]]*\]\(([^)]+)\)", text)
        targets += re.findall(r"""href=["']([^"']+)["']""", text)
        for target in targets:
            if target.startswith(("http://", "https://", "#", "mailto:")):
                continue
            target = target.split("#", 1)[0].split("?", 1)[0]
            if not target:
                continue
            checked += 1
            if not (path.parent / target).resolve().exists():
                missing.append(f"{path.relative_to(ROOT)} -> {target}")
    if missing:
        raise AssertionError("broken local links:\n" + "\n".join(missing))
    return checked


def check_package_platform() -> str:
    package = (ROOT / "Package.swift").read_text(encoding="utf-8")
    if '.macOS(.v26)' not in package:
        raise AssertionError("expected macOS 26 platform declaration")
    return "macOS 26"


def main() -> None:
    required = check_required_files()
    links = check_links()
    platform = check_package_platform()
    print(json.dumps({
        "status": "passed",
        "required_files": required,
        "local_links": links,
        "platform": platform,
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

