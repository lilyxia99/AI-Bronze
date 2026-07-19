#!/usr/bin/env python3
"""
terminalFiction Player
Play a .txt animation file in the terminal.
Frames are separated by —f— on its own line.
Loops by default. Ctrl+C to stop.

Usage:
  python player.py <file.txt> [fps] [--once]
"""

import os
import sys
import time

FRAME_SEP = "—f—"
TRANSITION_MARKER = "—type:"


def clear():
    # Move cursor to top-left and clear screen
    sys.stdout.write("\033[H\033[J")
    sys.stdout.flush()


def read_frames(filepath):
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()
    parts = content.split(FRAME_SEP)
    frames = []
    for p in parts:
        # Strip transition markers from displayed content
        lines = [l for l in p.split("\n") if not l.strip().startswith(TRANSITION_MARKER)]
        frame = "\n".join(lines).strip("\n")
        if frame.strip():
            frames.append(frame)
    return frames


def play(filepath, fps=2.0, loop=True):
    frames = read_frames(filepath)
    if not frames:
        print(f"No frames found in: {filepath}")
        return

    try:
        first_pass = True
        while first_pass or loop:
            first_pass = False
            for frame in frames:
                clear()
                print(frame)
                time.sleep(1.0 / fps)
    except KeyboardInterrupt:
        clear()


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    filepath = sys.argv[1]
    if not os.path.exists(filepath):
        print(f"File not found: {filepath}")
        sys.exit(1)

    fps = 2.0
    loop = True

    for arg in sys.argv[2:]:
        if arg == "--once":
            loop = False
        else:
            try:
                fps = float(arg)
            except ValueError:
                pass

    play(filepath, fps, loop)


if __name__ == "__main__":
    main()
