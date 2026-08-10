#!/usr/bin/env python3
"""Watch a Codex agent work, in a window of its own.

A file rather than a heredoc, deliberately. The hand-rolled version of this died
in three levels of shell quoting before Python ever parsed it, which is the same
lesson duet-goal.py records.

Standard library and ANSI only. No curses, no dependencies, and no assumption
that the terminal is 80 columns, which is what made the previous viewer wrap
absolute paths across three lines.

Layout is a sticky header, a scrolling body and a sticky footer, done with a
DECSTBM scroll region so the body scrolls under fixed furniture. SIGWINCH
redraws rather than corrupting.

    duet · rescue · [2/11] Truth audit          gpt-5.6-terra · xhigh

      $  git diff --stat -- docs/vendor
      ~  phases/2/out.md
      >  Truth audit complete. Worst finding: ordinary browser trading
         skips sanctions screening.

    130 events · 8.9M in · 37k out · 4m12s                 goal: active

Usage:  duet-tail.py <stream.jsonl> [--title "rescue · [2/11] Truth audit"]
                                    [--root /path/to/run] [--once]
"""

import argparse
import json
import os
import re
import shutil
import signal
import sys
import time

# Duet's palette, so a window opened by Duet looks like Duet.
DIM = "\033[2m"
BOLD = "\033[1m"
RESET = "\033[0m"
BLUE = "\033[38;5;75m"
GREEN = "\033[38;5;71m"
YELLOW = "\033[38;5;179m"
RED = "\033[38;5;167m"
GREY = "\033[38;5;245m"
BG = "\033[48;5;236m"

ALT_ON, ALT_OFF = "\033[?1049h", "\033[?1049l"
HIDE, SHOW = "\033[?25l", "\033[?25h"

# Both stream shapes, verified live and documented at the top of
# duet-progress.sh: the app-server uses slashed method names with the payload
# under params, codex exec --json uses dotted type names with it at top level.
IGNORE = ("mcpServer/", "remoteControl/")


def size():
    s = shutil.get_terminal_size((100, 30))
    return max(s.columns, 40), max(s.lines, 10)


def human(n):
    if n >= 1_000_000:
        return f"{n/1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n/1_000:.0f}k"
    return str(n)


def elapsed(start):
    s = int(time.time() - start)
    return f"{s//60}m{s%60:02d}s" if s >= 60 else f"{s}s"


def visible_len(s):
    return len(re.sub(r"\033\[[0-9;]*m", "", s))


def clip(s, width):
    """Truncate at the END. The old viewer cut the middle out of commands,
    which removed the part that said what the command was actually for."""
    s = " ".join(s.split())
    if len(s) <= width:
        return s
    return s[: max(0, width - 3)] + "..."


def wrap(text, width, indent):
    text = " ".join(text.split())
    out, line = [], ""
    for word in text.split(" "):
        if line and len(line) + 1 + len(word) > width:
            out.append(line)
            line = word
        else:
            line = f"{line} {word}".strip()
    if line:
        out.append(line)
    return [out[0]] + [" " * indent + l for l in out[1:]] if out else []


class View:
    def __init__(self, path, title, root):
        self.path = path
        self.title = title
        self.root = root.rstrip("/") if root else ""
        self.start = time.time()
        self.events = 0
        self.tok_in = self.tok_out = self.tok_reason = 0
        self.goal = ""
        self.model = ""
        self.seen = set()          # item ids, so nothing prints twice
        self.body = []
        self.w, self.h = size()

    # ---------- rendering ----------------------------------------------

    def frame(self):
        """Header, footer and the scroll region between them."""
        self.w, self.h = size()
        top, bottom = 2, self.h - 2
        left = f" {BOLD}duet{RESET} {DIM}·{RESET} {self.title}"
        right = f"{self.model}{RESET} " if self.model else ""
        pad = max(1, self.w - visible_len(left) - visible_len(right) - 1)
        sys.stdout.write(f"\033[1;1H\033[2K{left}{' ' * pad}{DIM}{right}")

        bits = [f"{self.events} events"]
        if self.tok_in:
            bits.append(f"{human(self.tok_in)} in")
        if self.tok_out:
            bits.append(f"{human(self.tok_out)} out")
        if self.tok_reason:
            bits.append(f"{human(self.tok_reason)} reasoning")
        bits.append(elapsed(self.start))
        fleft = f" {DIM}{' · '.join(bits)}{RESET}"
        colour = {"complete": GREEN, "active": BLUE}.get(self.goal, YELLOW)
        fright = f"{colour}goal: {self.goal}{RESET} " if self.goal else ""
        fpad = max(1, self.w - visible_len(fleft) - visible_len(fright) - 1)
        sys.stdout.write(f"\033[{self.h};1H\033[2K{fleft}{' ' * fpad}{fright}")

        sys.stdout.write(f"\033[{top};{bottom}r\033[{bottom};1H")
        sys.stdout.flush()

    def emit(self, lines):
        for l in lines:
            sys.stdout.write(f"\r\033[K{l}\n")
        sys.stdout.flush()

    # ---------- parsing -------------------------------------------------

    def rel(self, p):
        """Shorten paths so they stop wrapping across three lines.

        Under the run root, strip it. Outside it, keep the last few components,
        because an absolute path from another checkout is still mostly noise and
        the tail is the part that identifies the file."""
        if self.root and p.startswith(self.root):
            return p[len(self.root):].lstrip("/")
        if p.startswith("/") and p.count("/") > 3:
            return ".../" + "/".join(p.split("/")[-3:])
        return p

    def handle(self, m):
        if not isinstance(m, dict):
            return []
        method = (m.get("method") or m.get("type") or "").replace(".", "/")
        if method.startswith(IGNORE):
            return []
        self.events += 1
        p = m.get("params") if isinstance(m.get("params"), dict) else m
        body = self.w - 7

        if method == "thread/tokenUsage/updated":
            t = (p.get("tokenUsage") or {}).get("total") or {}
            self.tok_in = t.get("inputTokens", self.tok_in)
            self.tok_out = t.get("outputTokens", self.tok_out)
            self.tok_reason = t.get("reasoningOutputTokens", self.tok_reason)
            return []

        if method == "thread/goal/updated":
            g = p.get("goal") or {}
            self.goal = g.get("status", self.goal)
            return []

        if method in ("item/started", "item/completed"):
            item = p.get("item") if isinstance(p.get("item"), dict) else None
            if not item:
                return []
            # Both started and completed carry the same payload. Printing on
            # each is why the previous viewer showed everything twice.
            key = f"{item.get('id')}:{item.get('type')}"
            if key in self.seen:
                return []
            kind = item.get("type") or ""
            if kind == "command_execution" and item.get("command"):
                self.seen.add(key)
                return [f"   {BLUE}${RESET} {DIM}{clip(item['command'], body)}{RESET}"]
            if kind == "file_change" or item.get("path"):
                self.seen.add(key)
                return [f"   {YELLOW}~{RESET} {clip(self.rel(str(item.get('path', ''))), body)}"]
            if kind == "agent_message" and isinstance(item.get("text"), str):
                self.seen.add(key)
                txt = self.rel(item["text"])
                return [f"   {GREEN}>{RESET} {l}" if i == 0 else f"{l}"
                        for i, l in enumerate(wrap(txt, body, 6))]
            if kind == "reasoning":
                return []
            return []

        if method == "item/agentMessage/delta":
            return []          # the completed item carries the whole thing
        return []

    # ---------- the loop ------------------------------------------------

    def run(self, once=False):
        sys.stdout.write(ALT_ON + HIDE + "\033[2J")
        signal.signal(signal.SIGWINCH, lambda *_: self.frame())
        self.frame()
        pos = 0
        try:
            while True:
                if os.path.exists(self.path):
                    with open(self.path, errors="replace") as fh:
                        fh.seek(pos)
                        # readline() rather than `for line in fh`: iterating a
                        # file uses a read-ahead buffer and Python then refuses
                        # tell() with "telling position disabled by next()".
                        # A partial last line is left for the next pass, so a
                        # half-written event is never parsed.
                        while True:
                            line = fh.readline()
                            if not line:
                                break
                            if not line.endswith("\n"):
                                break
                            pos = fh.tell()
                            line = line.strip()
                            if not line:
                                continue
                            try:
                                m = json.loads(line)
                            except Exception:
                                continue
                            out = self.handle(m)
                            if out:
                                self.emit(out)
                self.frame()
                if once:
                    break
                time.sleep(0.4)
        except KeyboardInterrupt:
            pass
        finally:
            sys.stdout.write(f"\033[r{SHOW}{ALT_OFF}")
            sys.stdout.flush()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("stream")
    ap.add_argument("--title", default="codex")
    ap.add_argument("--root", default="")
    ap.add_argument("--model", default="")
    ap.add_argument("--once", action="store_true")
    a = ap.parse_args()
    v = View(a.stream, a.title, a.root)
    v.model = a.model
    v.run(once=a.once)


if __name__ == "__main__":
    main()
