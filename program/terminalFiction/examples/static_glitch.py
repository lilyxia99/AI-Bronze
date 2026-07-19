"""
Custom transition: Static Glitch
Simulates a TV/screen going to static before cutting to the next scene.
Place next to your scene files in the story folder.

Signature expected by main_runner.py:
  run(trigger=None, current="", next_content="")
"""

import sys
import time
import random


def clear():
    sys.stdout.write("\033[H\033[J")
    sys.stdout.flush()


def _wait_for_trigger(trigger):
    if trigger:
        prompt = f"\n  ┌─ type '{trigger}' to continue ─┐\n  > "
        while True:
            try:
                response = input(prompt).strip()
                if response.lower() == trigger.lower():
                    break
            except (EOFError, KeyboardInterrupt):
                sys.exit(0)
    else:
        try:
            input("\n  [ Press Enter to continue ]")
        except (EOFError, KeyboardInterrupt):
            sys.exit(0)


def run(trigger=None, current="", next_content=""):
    _wait_for_trigger(trigger)

    static_chars = "▓▒░█ ▓▒░▓▒▓░█▒ ░▓█▒░"
    lines = current.split("\n") if current else [""] * 20
    width = max((len(l) for l in lines), default=60)
    height = max(len(lines), 20)

    # Phase 1: growing static from bottom
    for wave in range(height + 1):
        sys.stdout.write("\033[H")
        out = []
        for row in range(height):
            if row >= height - wave:
                out.append("".join(random.choice(static_chars) for _ in range(width)))
            else:
                out.append(lines[row] if row < len(lines) else "")
        sys.stdout.write("\n".join(out))
        sys.stdout.flush()
        time.sleep(0.03)

    # Phase 2: full static buzz
    for _ in range(8):
        sys.stdout.write("\033[H")
        for row in range(height):
            sys.stdout.write("".join(random.choice(static_chars) for _ in range(width)) + "\n")
        sys.stdout.flush()
        time.sleep(0.05)

    # Phase 3: fade static to blank
    density = len(static_chars) - 1
    for step in range(density + 1):
        sparse = static_chars[:density - step] or " "
        sys.stdout.write("\033[H")
        for row in range(height):
            sys.stdout.write("".join(random.choice(sparse) for _ in range(width)) + "\n")
        sys.stdout.flush()
        time.sleep(0.06)

    clear()
