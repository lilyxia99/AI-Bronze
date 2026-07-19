#!/usr/bin/env python3
"""
terminalFiction Main Runner
Reads a main.txt story file and runs the visual novel.

main.txt format (all on one line, or line-wrapped with →):
  scene1.txt → scene2.txt → scene3.txt-glitch.py → special.py → scene4.txt

Rules:
  • Entries separated by →
  • .txt entries are displayed as scenes (animated if multi-frame)
  • .py entries are run as special scripts (must define run())
  • A -suffix on a .txt entry names a transition script to use AFTER that scene
    e.g.  scene2.txt-myTransition.py  uses myTransition.py to exit scene2
  • If no transition is specified, the default is used (waits for —type: trigger or Enter)

Usage:
  python main_runner.py [main.txt] [fps]
  Defaults: main.txt = examples/main.txt, fps = 2
"""

import os
import sys
import time
import importlib.util

FRAME_SEP = "—f—"
TRANSITION_MARKER = "—type:"

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))


def clear():
    sys.stdout.write("\033[H\033[J")
    sys.stdout.flush()


# ─── File helpers ─────────────────────────────────────────────────────────────

def read_raw(filepath):
    with open(filepath, "r", encoding="utf-8") as f:
        return f.read()


def split_frames(content):
    parts = content.split(FRAME_SEP)
    return [p.strip("\n") for p in parts if p.strip()]


def visible_content(frame):
    """Strip transition markers from a frame for display."""
    lines = [l for l in frame.split("\n") if not l.strip().startswith(TRANSITION_MARKER)]
    return "\n".join(lines)


def get_trigger(filepath):
    """Return the —type: trigger word from the last frame, or None."""
    raw = read_raw(filepath)
    for line in reversed(raw.split("\n")):
        line = line.strip()
        if line.startswith(TRANSITION_MARKER):
            return line[len(TRANSITION_MARKER):].strip()
    return None


# ─── Scene display ────────────────────────────────────────────────────────────

def display_scene(filepath, fps=2.0):
    """
    Show a .txt scene. If it has multiple frames, animate them once,
    then hold on the last frame. Returns the full visible content of the last frame.
    """
    raw = read_raw(filepath)
    frames = split_frames(raw)
    if not frames:
        return ""

    if len(frames) > 1:
        for frame in frames[:-1]:
            clear()
            print(visible_content(frame))
            time.sleep(1.0 / fps)

    last = visible_content(frames[-1])
    clear()
    print(last)
    return last


# ─── Transition handling ───────────────────────────────────────────────────────

def load_module(path):
    spec = importlib.util.spec_from_file_location("_tf_module", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def run_transition(transition_path, trigger, current_content, next_content=""):
    """
    Execute a transition.
    transition_path may be:
      - None or ""              → use built-in default
      - "builtin:<name>"        → use named built-in (e.g. "builtin:glitch")
      - a .py file path         → load and call run(trigger, current, next_content)
    """
    # Resolve built-in name shorthand
    if not transition_path:
        _builtin("default", trigger, current_content, next_content)
        return

    if transition_path.startswith("builtin:"):
        name = transition_path.split(":", 1)[1]
        _builtin(name, trigger, current_content, next_content)
        return

    if not os.path.exists(transition_path):
        print(f"\n  [Warning: transition script not found: {transition_path}]")
        time.sleep(1)
        _builtin("default", trigger, current_content, next_content)
        return

    mod = load_module(transition_path)
    if hasattr(mod, "run"):
        mod.run(trigger=trigger, current=current_content, next_content=next_content)
    else:
        _builtin("default", trigger, current_content, next_content)


def _builtin(name, trigger, current, next_content):
    sys.path.insert(0, SCRIPT_DIR)
    import transition as T
    fn = T.get(name)
    fn(trigger=trigger, current=current, next_content=next_content)


# ─── main.txt parser ──────────────────────────────────────────────────────────

def parse_main(main_filepath):
    """
    Parse main.txt and return a list of (entry, transition_override) tuples.

    entry             — filename (.txt or .py) relative to story dir
    transition_override — transition script filename, or None for default

    Format:  a.txt → b.txt-t.py → c.py → d.txt
    Comments: lines beginning with # are ignored.
    """
    raw = read_raw(main_filepath)

    # Strip comments and collapse to one string
    lines = []
    for line in raw.split("\n"):
        stripped = line.strip()
        if stripped and not stripped.startswith("#"):
            lines.append(stripped)
    content = "".join(lines)

    tokens = [t.strip() for t in content.split("→") if t.strip()]

    entries = []
    for token in tokens:
        # Check for attached transition:  filename.txt-transitionScript.py
        # We split on the LAST dash that precedes a .py suffix
        transition = None
        if "-" in token:
            dash_idx = token.rfind("-")
            suffix = token[dash_idx + 1:]
            if suffix.endswith(".py"):
                transition = suffix
                token = token[:dash_idx]
        entries.append((token, transition))

    return entries


# ─── Story runner ─────────────────────────────────────────────────────────────

def run_story(main_filepath, fps=2.0):
    story_dir = os.path.dirname(os.path.abspath(main_filepath))
    entries = parse_main(main_filepath)

    if not entries:
        print("main.txt is empty or has no valid entries.")
        return

    clear()

    for i, (entry, transition_override) in enumerate(entries):
        is_last = (i == len(entries) - 1)

        entry_path = os.path.join(story_dir, entry) if not os.path.isabs(entry) else entry

        if not os.path.exists(entry_path):
            clear()
            print(f"\n  [Missing file: {entry}]\n")
            time.sleep(1.5)
            continue

        # ── .txt scene ────────────────────────────────────────────────────────
        if entry.endswith(".txt"):
            last_content = display_scene(entry_path, fps)

            if is_last:
                break

            trigger = get_trigger(entry_path)

            # Resolve transition script path
            if transition_override:
                trans_path = os.path.join(story_dir, transition_override)
            else:
                trans_path = None

            # Peek at next entry's content for transition effects
            next_entry, _ = entries[i + 1]
            next_path = os.path.join(story_dir, next_entry) if not os.path.isabs(next_entry) else next_entry
            next_content = ""
            if os.path.exists(next_path) and next_entry.endswith(".txt"):
                raw = read_raw(next_path)
                next_frames = split_frames(raw)
                if next_frames:
                    next_content = visible_content(next_frames[0])

            run_transition(trans_path, trigger, last_content, next_content)

        # ── .py special script ────────────────────────────────────────────────
        elif entry.endswith(".py"):
            mod = load_module(entry_path)
            if hasattr(mod, "run"):
                mod.run()
            # After a special script, if not last, just continue
            if not is_last:
                time.sleep(0.3)

        else:
            clear()
            print(f"\n  [Unknown entry type: {entry}]\n")
            time.sleep(1.5)

    # ── Story end ─────────────────────────────────────────────────────────────
    clear()
    print("\n\n\n")
    print("   ╔═══════════════════╗")
    print("   ║       END         ║")
    print("   ╚═══════════════════╝")
    print("\n\n")
    try:
        input("   [ Press Enter to exit ]")
    except (EOFError, KeyboardInterrupt):
        pass
    clear()


# ─── Entry point ──────────────────────────────────────────────────────────────

if __name__ == "__main__":
    main_file = sys.argv[1] if len(sys.argv) > 1 else os.path.join(SCRIPT_DIR, "examples", "main.txt")
    fps_arg = float(sys.argv[2]) if len(sys.argv) > 2 else 2.0

    if not os.path.exists(main_file):
        print(f"Error: {main_file} not found.")
        sys.exit(1)

    run_story(main_file, fps_arg)
