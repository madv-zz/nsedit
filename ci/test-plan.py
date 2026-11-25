#!/usr/bin/env python3
"""Check the test plan in a pull request description: every checkbox must be ticked.

A pull request is only ready when everything in its test plan was really done. An open box
(`- [ ] ...`) means something is still missing, so the check fails and lists what is open.
A description without any checkbox also fails (no test plan), except for pull requests by
a bot such as Dependabot (pass --author).

Boxes inside code blocks (``` or ~~~) and HTML comments do not count.

The description is read from stdin. Locally, for pull request <n>:
    gh api repos/madv-zz/nsedit/pulls/<n> --jq .body | python3 ci/test-plan.py
"""
import argparse
import re
import sys

BOX = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s+\[([ xX])\]\s*(.*)$")
FENCE = re.compile(r"^\s*(```|~~~)")
COMMENT = re.compile(r"<!--.*?-->", re.DOTALL)


def checkboxes(body):
    """(ticked, text) for every checkbox outside code blocks and HTML comments."""
    boxes, fence = [], None
    for line in COMMENT.sub("", body.replace("\r\n", "\n")).splitlines():
        match = FENCE.match(line)
        if match:
            if fence is None:
                fence = match.group(1)
            elif match.group(1) == fence:
                fence = None
            continue
        if fence is None:
            box = BOX.match(line)
            if box:
                boxes.append((box.group(1) != " ", box.group(2).strip()))
    return boxes


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--author", default="", help="login of the pull request author")
    args = parser.parse_args()

    boxes = checkboxes(sys.stdin.read())
    open_items = [text for ticked, text in boxes if not ticked]
    if open_items:
        print(f"Test plan: {len(open_items)} of {len(boxes)} items not ticked:")
        for text in open_items:
            print(f"  - [ ] {text}")
        print("Do them and tick them in the description; this check runs again when the description changes.")
        return 1
    if not boxes:
        if args.author.endswith("[bot]"):
            print(f"No test plan; allowed for {args.author}.")
            return 0
        print("No test plan: the description has no checkboxes (- [x] ...). Add what was tested.")
        return 1
    print(f"Test plan: all {len(boxes)} items ticked.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
