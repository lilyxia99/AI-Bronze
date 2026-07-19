#!/usr/bin/env python3
"""
terminalFiction Transition Library
Built-in transition effects between scenes.

Each transition function signature:  fn(trigger=None, current="", next_content="")
  trigger       — the word the user must type (from —type:), or None for Enter
  current       — current scene content string (may be unused)
  next_content  — next scene content string (may be unused)

Used by main_runner.py. Can also be tested standalone:
  python transition.py <effect_name>
  Available: default, dissolve, glitch, wipe, typewriter
"""

import os
import sys
import time
import random

TRANSITION_MARKER = "—type:"


def clear():
    sys.stdout.write("\033[H\033[J")
    sys.stdout.flush()


def _wait_for_trigger(trigger):
    """Block until user types the trigger word (or Enter if trigger is None)."""
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


# ─── Built-in Effects ────────────────────────────────────────────────────────

def default(trigger=None, current="", next_content=""):
    """Wait for trigger input, then clear."""
    _wait_for_trigger(trigger)
    clear()


def dissolve(trigger=None, current="", next_content="", steps=20, delay=0.04):
    """Randomly replace characters of current with next."""
    _wait_for_trigger(trigger)

    if not current or not next_content:
        clear()
        return

    cur = list(current)
    nxt = list(next_content)
    length = max(len(cur), len(nxt))
    cur += [" "] * (length - len(cur))
    nxt += [" "] * (length - len(nxt))

    indices = [i for i in range(length) if cur[i] != nxt[i]]
    random.shuffle(indices)
    chunk = max(1, len(indices) // steps)

    result = list(cur)
    for start in range(0, len(indices), chunk):
        for idx in indices[start : start + chunk]:
            result[idx] = nxt[idx]
        sys.stdout.write("\033[H")
        sys.stdout.write("".join(result))
        sys.stdout.flush()
        time.sleep(delay)

    clear()


def glitch(trigger=None, current="", next_content="", duration=1.2, delay=0.06):
    """Rapidly flash garbled characters before revealing next scene."""
    _wait_for_trigger(trigger)

    glitch_chars = "█▓▒░╔╗╚╝║═╠╣╦╩╬@#%&*!?/"
    lines = current.split("\n") if current else [""]
    width = max((len(l) for l in lines), default=40)
    height = len(lines)

    end_time = time.time() + duration
    while time.time() < end_time:
        sys.stdout.write("\033[H")
        for row in range(height):
            base = lines[row] if row < len(lines) else ""
            garbled = []
            for ch in base:
                if ch != "\n" and random.random() < 0.3:
                    garbled.append(random.choice(glitch_chars))
                else:
                    garbled.append(ch)
            sys.stdout.write("".join(garbled) + "\n")
        sys.stdout.flush()
        time.sleep(delay)

    clear()


def wipe(trigger=None, current="", next_content="", delay=0.04):
    """Wipe current scene downward, revealing next scene line by line."""
    _wait_for_trigger(trigger)

    cur_lines = current.split("\n") if current else []
    nxt_lines = next_content.split("\n") if next_content else []
    total = max(len(cur_lines), len(nxt_lines))

    for i in range(total + 1):
        sys.stdout.write("\033[H\033[J")
        output = []
        for row in range(total):
            if row < i:
                output.append(nxt_lines[row] if row < len(nxt_lines) else "")
            else:
                output.append(cur_lines[row] if row < len(cur_lines) else "")
        sys.stdout.write("\n".join(output))
        sys.stdout.flush()
        time.sleep(delay)

    clear()


def typewriter(trigger=None, current="", next_content="", speed=0.03):
    """Clear then type out next scene character by character."""
    _wait_for_trigger(trigger)
    clear()

    for ch in next_content:
        sys.stdout.write(ch)
        sys.stdout.flush()
        if ch not in (" ", "\n"):
            time.sleep(speed)


# ─── Registry ────────────────────────────────────────────────────────────────

TRANSITIONS = {
    "default": default,
    "dissolve": dissolve,
    "glitch": glitch,
    "wipe": wipe,
    "typewriter": typewriter,
}


def get(name):
    """Return a transition function by name, falling back to default."""
    return TRANSITIONS.get(name, default)


# ─── CLI test ────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Available transitions:", ", ".join(TRANSITIONS))
        sys.exit(0)

    name = sys.argv[1]
    if name not in TRANSITIONS:
        print(f"Unknown: {name}. Available: {', '.join(TRANSITIONS)}")
        sys.exit(1)

    sample = "   Hello from the current scene.\n   Press Enter...\n"
    nxt = "   Hello from the NEXT scene.\n"
    print(sample)
    TRANSITIONS[name](trigger=None, current=sample, next_content=nxt)
    print(nxt)
