#!/usr/bin/env python3
"""Eligibility filter for scripts/ai-solve-issue-queue.sh (issue #227).

Reads a `gh issue list --json number,title,body,labels,createdAt` JSON array
from stdin, prints one "<number>\t<title>" line per eligible issue, oldest
first. A separate script file (not inline `python - <<EOF`) because piping
JSON into a heredoc'd `python -` invocation doesn't work: `-` makes Python
read the program itself from stdin, which already consumes the heredoc,
leaving nothing for the script's own sys.stdin.read() to see.
"""
from __future__ import annotations

import json
import re
import sys

# "ai:ready" is not checked here — the caller's `gh issue list --label
# ai:ready` query already guarantees every issue in stdin has it.
BLOCKED_LABEL = "ai:blocked"
RISK_LABELS = {"ai:risk-low", "ai:docs-only", "ai:test-only"}

# Cheap pre-filter before solve-issue.sh's own (heavier) risk classification
# even runs. Intentionally redundant with classify_issue_risk() in
# ai-solve-issue.sh — a gap here is still caught by that gate before any
# commit/push/PR, but this filter keeps the queue from even starting a run
# that's almost certainly going to be blocked anyway.
FORBIDDEN = re.compile(
    r"(secret|credential|password|\btoken\b|\bdeploy\b|\bvps\b|\brelease\b|"
    r"\bdestroy\b|\.github/workflows|github actions)",
    re.IGNORECASE,
)


def main() -> int:
    issues = json.load(sys.stdin)
    eligible = []
    for issue in issues:
        labels = {label["name"] for label in issue.get("labels", [])}
        if BLOCKED_LABEL in labels:
            continue
        if not (labels & RISK_LABELS):
            continue
        text = f"{issue.get('title', '')}\n{issue.get('body') or ''}"
        if FORBIDDEN.search(text):
            continue
        eligible.append(issue)

    eligible.sort(key=lambda i: i.get("createdAt", ""))
    for issue in eligible:
        print(f"{issue['number']}\t{issue['title']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
