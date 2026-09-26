#!/usr/bin/env python3
"""An independent walk of a PR's review threads, joined to `contrib in --json`.

`contrib` never consults `isResolved`, by design (REVIEW.md: nothing is discharged by
resolution). This script does, so that the two readings can be compared thread by thread.
It is the oracle issue #7 was written from: a second code path that fetches the same
threads with its own GraphQL query and classifies them without any of the kit's code.

Per thread it reports the kit's state beside what GitHub and the asker say:
  - isResolved, and resolvedBy with the app suffix `[bot]` normalised away;
  - whether I replied, and the asker-login replies before/after my last one;
  - whether each asker reply opens with the reviewer's verdict phrase
    (default: Devin Review's `✅ **Resolved**:`), matched on the opening lines of
    stripped prose only — the lesson `SupersessionDetector` records.

It then sorts the disagreements into the four cases of issue #7:
  1  confirmed-before-reply    kit says answered-claimed; the asker's verdict precedes my reply
  2  one-login-two-roles       kit says open-ask; the asker's login replied (fix session or verdict)
  3  correction-as-confirm     kit says answered-confirmed; the asker's later reply is not a verdict
  4  unresolved                GitHub says the thread is still open (flagged when a closed PR
                               quiets it by default)

Nothing is written anywhere but stdout and, with --capture, the given directory. The kit's
snapshot is left untouched (`--no-snapshot`).

Exit status: 0 on a complete walk, 1 when a tool fails, 2 on an anomaly — a truncated
comment page, or a thread count that differs from the kit's own `inline threads` counter.
A zero is only a zero when the provenance lines above it show what was examined.

Usage:
  scripts/resolution-crosscheck.py OWNER/REPO PR [PR ...] [--capture DIR] [--json]
      [--verdict-phrase TEXT] [--contrib PATH] [--me LOGIN]
"""

import argparse
import json
import re
import subprocess
import sys
from collections import Counter

QUERY = """
query($owner:String!, $name:String!, $n:Int!, $endCursor:String) {
  repository(owner:$owner, name:$name) {
    pullRequest(number:$n) {
      state
      reviewThreads(first:50, after:$endCursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          isResolved isOutdated path
          resolvedBy { login }
          comments(first:100) {
            totalCount
            pageInfo { hasNextPage }
            nodes { databaseId author { login } createdAt url body }
          }
        }
      }
    }
  }
}
"""


class ToolFailure(Exception):
    pass


def run(cmd):
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise ToolFailure(f"{' '.join(cmd[:4])}… exited {proc.returncode}: {proc.stderr.strip()[:400]}")
    if not proc.stdout.strip():
        # `gh` exits 0 on an empty result; an empty answer is a failure to answer.
        raise ToolFailure(f"{' '.join(cmd[:4])}… exited 0 with no output")
    return proc.stdout


def json_documents(text):
    """`gh api --paginate` prints one JSON document per page, concatenated."""
    dec, i, docs = json.JSONDecoder(), 0, []
    while i < len(text):
        while i < len(text) and text[i].isspace():
            i += 1
        if i >= len(text):
            break
        doc, i = dec.raw_decode(text, i)
        docs.append(doc)
    return docs


def fetch_threads(owner, name, pr):
    out = run(["gh", "api", "graphql", "--paginate", "-f", f"query={QUERY}",
               "-F", f"owner={owner}", "-F", f"name={name}", "-F", f"n={pr}"])
    pages = json_documents(out)
    state = pages[0]["data"]["repository"]["pullRequest"]["state"]
    nodes = [n for p in pages for n in p["data"]["repository"]["pullRequest"]["reviewThreads"]["nodes"]]
    return state, nodes, pages


def strip_prose(body):
    """Visible prose: no HTML comments, no Devin badge block, no tags, no blank lines."""
    body = re.sub(r"<!--.*?-->", "", body, flags=re.S)
    body = re.sub(r"<a href=.*?</a>", "", body, flags=re.S)
    body = re.sub(r"<[^>]+>", "", body)
    return [line.strip() for line in body.split("\n") if line.strip()]


def is_verdict(body, phrase):
    # Opening lines only: a reply that *mentions* the phrase mid-sentence is not a verdict.
    return " ".join(strip_prose(body)[:2]).startswith(phrase)


def normalise(login):
    return (login or "").removesuffix("[bot]").lower()


def classify(thread, me, phrase):
    comments = thread["comments"]["nodes"]
    root, replies = comments[0], comments[1:]
    asker = normalise(root["author"]["login"])
    mine = [c for c in replies if normalise(c["author"]["login"]) == me]
    asker_replies = [c for c in replies
                     if normalise(c["author"]["login"]) == asker and normalise(c["author"]["login"]) != me]
    last_mine = mine[-1]["createdAt"] if mine else None
    after = [c for c in asker_replies if last_mine and c["createdAt"] > last_mine]
    before = [c for c in asker_replies if not last_mine or c["createdAt"] <= last_mine]
    title = (strip_prose(root["body"]) or ["(no prose)"])[0]
    return {
        "id": f"discussion_r{root['databaseId']}",
        "url": root["url"],
        "title": title[:90],
        "isResolved": thread["isResolved"],
        "resolvedBy": normalise((thread.get("resolvedBy") or {}).get("login")) or None,
        "resolvedByAsker": normalise((thread.get("resolvedBy") or {}).get("login")) == asker,
        "iReplied": bool(mine),
        "askerBefore": ["verdict" if is_verdict(c["body"], phrase) else "other" for c in before],
        "askerAfter": ["verdict" if is_verdict(c["body"], phrase) else "other" for c in after],
    }


def case_of(row, closed):
    s = row["state"]
    if not row["isResolved"]:
        return "4 unresolved" + (" (quieted: closed PR)" if closed and s == "answered-claimed" else "")
    if s == "answered-claimed" and "verdict" in row["askerBefore"]:
        return "1 confirmed-before-reply"
    if s == "open-ask" and (row["askerBefore"] or row["askerAfter"]):
        return "2 one-login-two-roles"
    if s == "answered-confirmed" and row["askerAfter"] and "verdict" not in row["askerAfter"]:
        return "3 correction-as-confirm"
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("repo")
    ap.add_argument("prs", nargs="+", type=int)
    ap.add_argument("--verdict-phrase", default="✅ **Resolved**:")
    ap.add_argument("--contrib", default="contrib")
    ap.add_argument("--me", help="my login (default: gh api user)")
    ap.add_argument("--capture", metavar="DIR", help="save raw GraphQL pages and contrib JSON here")
    ap.add_argument("--json", action="store_true", help="emit every joined row as JSON")
    args = ap.parse_args()
    owner, name = args.repo.split("/", 1)

    try:
        me = normalise(args.me or run(["gh", "api", "user", "--jq", ".login"]).strip())
        rows, anomalies, provenance = [], [], []
        for pr in args.prs:
            state, threads, pages = fetch_threads(owner, name, pr)
            kit = json.loads(run([args.contrib, "in", args.repo, "--pr", str(pr),
                                  "--all", "--json", "--no-snapshot"]))
            counters = {c["label"]: c["value"] for c in kit["provenance"]["counters"]}
            items = {i["id"]: i for i in kit["items"]}
            provenance.append(f"#{pr} {state.lower()}: {len(threads)} threads (GraphQL), "
                              f"{counters.get('inline threads')} (contrib), {len(kit['items'])} contrib items")
            if counters.get("inline threads") != len(threads):
                anomalies.append(f"#{pr}: thread count GraphQL {len(threads)} ≠ contrib {counters.get('inline threads')}")
            if args.capture:
                with open(f"{args.capture}/pr-{pr}.threads.graphql.json", "w") as f:
                    json.dump(pages, f, ensure_ascii=False, indent=1)
                with open(f"{args.capture}/pr-{pr}.contrib.json", "w") as f:
                    json.dump(kit, f, ensure_ascii=False, indent=1)
            for t in threads:
                if t["comments"]["pageInfo"]["hasNextPage"]:
                    anomalies.append(f"#{pr}: a thread has more than 100 comments — truncated")
                row = classify(t, me, args.verdict_phrase)
                row["pr"] = pr
                item = items.get(row["id"])
                row["state"] = item["state"] if item else "MISSING"
                if not item:
                    anomalies.append(f"#{pr}: {row['id']} has no contrib item")
                row["case"] = case_of(row, state != "OPEN")
                rows.append(row)
    except ToolFailure as e:
        print(f"tool failure: {e}", file=sys.stderr)
        return 1

    if args.json:
        json.dump({"provenance": provenance, "anomalies": anomalies, "rows": rows},
                  sys.stdout, ensure_ascii=False, indent=1)
        print()
    else:
        print("— provenance —")
        for line in provenance:
            print("  " + line)
        print(f"  me={me}  verdict phrase={args.verdict_phrase!r}  rows={len(rows)}")
        print("\n— contrib state × GitHub resolution × asker replies —")
        table = Counter((r["pr"], r["state"], r["isResolved"], r["iReplied"],
                         "+".join(r["askerBefore"]) or "-", "+".join(r["askerAfter"]) or "-") for r in rows)
        print(f"  {'PR':>3} {'contrib state':20} {'resolved':8} {'I replied':9} {'asker before me':16} {'asker after me':15} n")
        for k in sorted(table, key=str):
            print(f"  {k[0]:>3} {k[1]:20} {str(k[2]):8} {str(k[3]):9} {k[4][:16]:16} {k[5][:15]:15} {table[k]}")
        print("\n— disagreements, by issue #7 case —")
        cases = Counter(r["case"] for r in rows if r["case"])
        for case in sorted(cases):
            print(f"  case {case}: {cases[case]}")
            for r in rows:
                if r["case"] == case:
                    print(f"      #{r['pr']} {r['state']:18} {r['title'][:60]}  {r['url']}")
        if not cases:
            print("  none")
    for a in anomalies:
        print(f"ANOMALY {a}", file=sys.stderr)
    return 2 if anomalies else 0


if __name__ == "__main__":
    sys.exit(main())
