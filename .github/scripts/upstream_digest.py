#!/usr/bin/env python3
import json
import re
import subprocess
import sys
from datetime import date, timedelta


UPSTREAM = "stevearc/oil.nvim"
TARGET = "barrettruth/canola.nvim"
UPSTREAM_MD = "doc/upstream.md"
LABEL = "upstream/digest"


def get_last_tracked_number():
    try:
        with open(UPSTREAM_MD) as f:
            content = f.read()
        numbers = re.findall(
            r"\[#(\d+)\]\(https://github\.com/stevearc/oil\.nvim", content
        )
        if numbers:
            return max(int(n) for n in numbers)
    except OSError:
        pass
    return None


def gh(*args):
    result = subprocess.run(
        ["gh"] + list(args),
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.strip()


def fetch_items(last_number, since_date):
    merged_prs = json.loads(
        gh(
            "pr", "list",
            "--repo", UPSTREAM,
            "--state", "merged",
            "--limit", "100",
            "--json", "number,title,mergedAt,url",
        )
    )

    open_issues = json.loads(
        gh(
            "issue", "list",
            "--repo", UPSTREAM,
            "--state", "open",
            "--limit", "100",
            "--json", "number,title,createdAt,url",
        )
    )

    open_prs = json.loads(
        gh(
            "pr", "list",
            "--repo", UPSTREAM,
            "--state", "open",
            "--limit", "100",
            "--json", "number,title,createdAt,url",
        )
    )

    if last_number is not None:
        merged_prs = [x for x in merged_prs if x["number"] > last_number]
        open_issues = [x for x in open_issues if x["number"] > last_number]
        open_prs = [x for x in open_prs if x["number"] > last_number]
    else:
        cutoff = since_date.isoformat()
        merged_prs = [x for x in merged_prs if x.get("mergedAt", "") >= cutoff]
        open_issues = [x for x in open_issues if x.get("createdAt", "") >= cutoff]
        open_prs = [x for x in open_prs if x.get("createdAt", "") >= cutoff]

    merged_prs.sort(key=lambda x: x["number"])
    open_issues.sort(key=lambda x: x["number"])
    open_prs.sort(key=lambda x: x["number"])

    return merged_prs, open_issues, open_prs


def format_row(item):
    num = item["number"]
    title = item["title"]
    url = item["url"]
    return f"- [#{num}]({url}) — {title}"


def build_body(merged_prs, open_issues, open_prs, last_number):
    if last_number is not None:
        summary = f"Items with number > #{last_number} (last entry in `doc/upstream.md`)."
    else:
        summary = "Last 30 days (could not parse `doc/upstream.md` for a baseline)."

    sections = [summary, ""]

    sections.append("## Merged PRs")
    if merged_prs:
        sections.extend(format_row(x) for x in merged_prs)
    else:
        sections.append("_None_")

    sections.append("")
    sections.append("## New open issues")
    if open_issues:
        sections.extend(format_row(x) for x in open_issues)
    else:
        sections.append("_None_")

    sections.append("")
    sections.append("## New open PRs")
    if open_prs:
        sections.extend(format_row(x) for x in open_prs)
    else:
        sections.append("_None_")

    return "\n".join(sections)


def main():
    last_number = get_last_tracked_number()
    since_date = date.today() - timedelta(days=30)

    merged_prs, open_issues, open_prs = fetch_items(last_number, since_date)

    total = len(merged_prs) + len(open_issues) + len(open_prs)
    if total == 0:
        print("No new upstream activity. Skipping issue creation.")
        return

    today = date.today().isoformat()
    title = f"upstream digest: week of {today}"
    body = build_body(merged_prs, open_issues, open_prs, last_number)

    gh(
        "issue", "create",
        "--repo", TARGET,
        "--title", title,
        "--label", LABEL,
        "--body", body,
    )

    print(f"Created digest issue: {title} ({total} items)")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as e:
        print(f"gh command failed: {e.stderr}", file=sys.stderr)
        sys.exit(1)
