#!/usr/bin/env python3
import json
import os
import re
import subprocess
import sys


UPSTREAM = "stevearc/oil.nvim"
UPSTREAM_MD = "doc/upstream.md"
FORK_REPO = os.environ.get("GITHUB_REPOSITORY", "")

PRS_HEADING = "## Upstream PRs"
ISSUES_HEADING = "## Issues"


def get_tracked_numbers():
    try:
        with open(UPSTREAM_MD) as f:
            content = f.read()
        return {
            int(n)
            for n in re.findall(
                r"\[#(\d+)\]\(https://github\.com/stevearc/oil\.nvim", content
            )
        }
    except OSError:
        return set()


def gh(*args):
    result = subprocess.run(
        ["gh"] + list(args),
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.strip()


def get_fork_created_at():
    if FORK_REPO:
        data = json.loads(gh("repo", "view", FORK_REPO, "--json", "createdAt"))
        return data["createdAt"]
    return None


def fetch_items(tracked):
    fork_created = get_fork_created_at()

    merged_prs = json.loads(
        gh(
            "pr", "list",
            "--repo", UPSTREAM,
            "--state", "merged",
            "--limit", "100",
            "--json", "number,title,url,mergedAt",
        )
    )
    open_prs = json.loads(
        gh(
            "pr", "list",
            "--repo", UPSTREAM,
            "--state", "open",
            "--limit", "100",
            "--json", "number,title,url",
        )
    )
    open_issues = json.loads(
        gh(
            "issue", "list",
            "--repo", UPSTREAM,
            "--state", "open",
            "--limit", "100",
            "--json", "number,title,url",
        )
    )

    merged_prs = [
        x for x in merged_prs
        if x["number"] not in tracked
        and (fork_created is None or x.get("mergedAt", "") >= fork_created)
    ]
    open_prs = [x for x in open_prs if x["number"] not in tracked]
    open_issues = [x for x in open_issues if x["number"] not in tracked]

    merged_prs.sort(key=lambda x: x["number"])
    open_prs.sort(key=lambda x: x["number"])
    open_issues.sort(key=lambda x: x["number"])

    return merged_prs, open_prs, open_issues


def append_to_section(content, heading, new_rows):
    lines = content.split("\n")
    in_section = False
    last_table_row = -1

    for i, line in enumerate(lines):
        if line.startswith("## "):
            in_section = line.strip() == heading
        if in_section and line.startswith("|"):
            last_table_row = i

    if last_table_row == -1:
        return content

    return "\n".join(
        lines[: last_table_row + 1] + new_rows + lines[last_table_row + 1 :]
    )


def main():
    tracked = get_tracked_numbers()

    merged_prs, open_prs, open_issues = fetch_items(tracked)

    total = len(merged_prs) + len(open_prs) + len(open_issues)
    if total == 0:
        print("No new upstream activity.")
        return

    with open(UPSTREAM_MD) as f:
        content = f.read()

    pr_rows = []
    for pr in open_prs:
        pr_rows.append(f"| [#{pr['number']}]({pr['url']}) | {pr['title']} | open |")
    for pr in merged_prs:
        pr_rows.append(
            f"| [#{pr['number']}]({pr['url']}) | {pr['title']} | merged — not cherry-picked |"
        )

    issue_rows = []
    for issue in open_issues:
        issue_rows.append(
            f"| [#{issue['number']}]({issue['url']}) | {issue['title']} | open |"
        )

    if pr_rows:
        content = append_to_section(content, PRS_HEADING, pr_rows)
    if issue_rows:
        content = append_to_section(content, ISSUES_HEADING, issue_rows)

    with open(UPSTREAM_MD, "w") as f:
        f.write(content)

    github_output = os.environ.get("GITHUB_OUTPUT")
    if github_output:
        with open(github_output, "a") as f:
            f.write("changed=true\n")

    print(
        f"Added {len(open_prs)} open PR(s), {len(merged_prs)} merged PR(s), "
        f"{len(open_issues)} issue(s) to {UPSTREAM_MD}"
    )


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as e:
        print(f"gh command failed: {e.stderr}", file=sys.stderr)
        sys.exit(1)
