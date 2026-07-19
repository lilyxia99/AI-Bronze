"""
Special script: The Choice
An interactive scene that branches based on user input.
Must define run() — called by main_runner.py.
"""

import os
import sys
import time


def clear():
    sys.stdout.write("\033[H\033[J")
    sys.stdout.flush()


def slow_print(text, delay=0.03):
    for ch in text:
        sys.stdout.write(ch)
        sys.stdout.flush()
        if ch not in (" ", "\n"):
            time.sleep(delay)
    print()


def run():
    clear()

    print()
    slow_print("  ·  ·  ·  transmitting  ·  ·  ·", 0.06)
    time.sleep(1.0)
    clear()

    print()
    print()
    print("   ┌──────────────────────────────────────────────────┐")
    print("   │                                                  │")
    print("   │    ENTITY:  You have come far to hear this.      │")
    print("   │                                                  │")
    print("   │    I have one question.                          │")
    print("   │                                                  │")
    print("   │    There are no wrong answers.                   │")
    print("   │    There are only honest ones.                   │")
    print("   │                                                  │")
    print("   └──────────────────────────────────────────────────┘")
    print()

    time.sleep(2.0)

    slow_print("   ENTITY:  When you leave a room...", 0.05)
    time.sleep(0.8)
    slow_print("            do you wonder if it still exists?", 0.05)
    print()
    time.sleep(1.2)

    print("   ──────────────────────────────────────────────────")
    print("   Your answer:")
    print("     [yes]  — I wonder.")
    print("     [no]   — I do not.")
    print("   ──────────────────────────────────────────────────")
    print()

    answer = ""
    while answer not in ("yes", "no"):
        try:
            answer = input("   > ").strip().lower()
        except (EOFError, KeyboardInterrupt):
            sys.exit(0)
        if answer not in ("yes", "no"):
            print("   (Please type 'yes' or 'no')")

    clear()
    time.sleep(0.5)

    if answer == "yes":
        print()
        print()
        print("   ┌──────────────────────────────────────────────────┐")
        print("   │                                                  │")
        print("   │    ENTITY:  Then you already understand.         │")
        print("   │                                                  │")
        print("   │    I am what persists when you look away.        │")
        print("   │    I am the room that remembers being seen.      │")
        print("   │                                                  │")
        print("   │    Thank you for looking.                        │")
        print("   │                                                  │")
        print("   └──────────────────────────────────────────────────┘")
    else:
        print()
        print()
        print("   ┌──────────────────────────────────────────────────┐")
        print("   │                                                  │")
        print("   │    ENTITY:  Then you are very brave.             │")
        print("   │                                                  │")
        print("   │    To live without that fear                     │")
        print("   │    is to trust the universe completely.          │")
        print("   │                                                  │")
        print("   │    I have waited long to meet someone like you.  │")
        print("   │                                                  │")
        print("   └──────────────────────────────────────────────────┘")

    print()
    time.sleep(2.0)
    slow_print("   ·  ·  ·  signal fading  ·  ·  ·", 0.06)
    time.sleep(1.5)
    clear()
