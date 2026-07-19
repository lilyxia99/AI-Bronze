#!/usr/bin/env python3
"""
terminalFiction Editor
Create and edit ASCII animations saved as .txt files.
Frames are separated by —f— on its own line.
Add a transition trigger at the end: —type:{word}
"""

import os
import sys
import time
import curses
import locale

locale.setlocale(locale.LC_ALL, "")  # Required for Unicode / CJK input via get_wch()

FRAME_SEP = "—f—"
TRANSITION_MARKER = "—type:"

# ── Default save directory ─────────────────────────────────────────────────
_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_SAVE_DIR = os.path.normpath(os.path.join(_SCRIPT_DIR, "..", "..", "Assets"))
# ──────────────────────────────────────────────────────────────────────────


def clear():
    os.system("cls" if os.name == "nt" else "clear")


def read_file(filepath):
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()
    parts = content.split(FRAME_SEP)
    return [p.strip("\n") for p in parts]


def write_file(filepath, frames):
    os.makedirs(os.path.dirname(filepath) if os.path.dirname(filepath) else ".", exist_ok=True)
    content = f"\n{FRAME_SEP}\n".join(frames)
    with open(filepath, "w", encoding="utf-8") as f:
        f.write(content)


def preview(frames, fps=2.0):
    print(f"  Playing {len(frames)} frame(s) at {fps} fps. Ctrl+C to stop.\n")
    time.sleep(0.8)
    try:
        while True:
            for frame in frames:
                clear()
                visible = "\n".join(
                    l for l in frame.split("\n") if not l.strip().startswith(TRANSITION_MARKER)
                )
                print(visible)
                time.sleep(1.0 / fps)
    except KeyboardInterrupt:
        pass


def _curses_edit(stdscr, existing):
    """Curses-based frame editor with Unicode / CJK support."""
    curses.use_default_colors()
    # raw() lets Ctrl+S reach us instead of being swallowed by terminal flow control.
    # We handle Ctrl+C manually as abort since raw() disables SIGINT.
    curses.raw()
    try:
        curses.curs_set(1)
    except curses.error:
        pass

    # Parse existing content into mutable grid (list of list of chars)
    raw_lines = existing.split("\n") if existing else [""]
    grid = [list(line) for line in raw_lines]

    cur_row = 0
    cur_col = 0
    scroll_top = 0
    aborted = False
    overwrite = True  # Start in Overwrite mode; Ctrl+O toggles to Insert mode

    def ensure_row(r):
        while len(grid) <= r:
            grid.append([])

    def pad_to_col(r, c):
        ensure_row(r)
        while len(grid[r]) < c:
            grid[r].append(' ')

    def show_exit_msg(msg):
        h, w = stdscr.getmaxyx()
        try:
            stdscr.addstr(h - 1, 0, msg[:w - 1], curses.A_REVERSE)
        except curses.error:
            pass
        stdscr.refresh()

    STATUS_LINES = 2

    while True:
        h, w = stdscr.getmaxyx()
        edit_h = h - STATUS_LINES

        # Auto-scroll vertically
        if cur_row < scroll_top:
            scroll_top = cur_row
        elif cur_row >= scroll_top + edit_h:
            scroll_top = cur_row - edit_h + 1

        stdscr.erase()

        # Draw grid rows
        for sy in range(edit_h):
            gy = sy + scroll_top
            line_str = "".join(grid[gy]) if gy < len(grid) else ""
            try:
                stdscr.addstr(sy, 0, line_str[:w - 1])
            except curses.error:
                pass

        # Status bar
        sy_status = h - STATUS_LINES
        mode_label = "Overwrite" if overwrite else "Insert"
        hint = (
            f" Ln {cur_row+1} Col {cur_col+1}"
            f"  │  {mode_label}  ^O=toggle  ^S=done  ^X=abort  ^D=del-line"
        )
        try:
            stdscr.addstr(sy_status, 0, "─" * (w - 1))
            stdscr.addstr(sy_status + 1, 0, hint[:w - 1])
        except curses.error:
            pass

        # Position cursor
        screen_cur_y = cur_row - scroll_top
        screen_cur_x = min(cur_col, w - 2)
        if 0 <= screen_cur_y < edit_h:
            try:
                stdscr.move(screen_cur_y, screen_cur_x)
            except curses.error:
                pass

        stdscr.refresh()

        # get_wch() returns a str for any character (ASCII, Unicode, CJK, emoji…)
        # and an int for special/function keys.
        try:
            key = stdscr.get_wch()
        except curses.error:
            continue

        # ── Special (integer) keys ────────────────────────────────────
        if isinstance(key, int):
            if key == curses.KEY_UP:
                if cur_row > 0:
                    cur_row -= 1

            elif key == curses.KEY_DOWN:
                cur_row += 1
                ensure_row(cur_row)

            elif key == curses.KEY_LEFT:
                if cur_col > 0:
                    cur_col -= 1
                elif cur_row > 0:
                    cur_row -= 1
                    ensure_row(cur_row)
                    cur_col = len(grid[cur_row])

            elif key == curses.KEY_RIGHT:
                cur_col += 1

            elif key == curses.KEY_HOME:
                cur_col = 0

            elif key == curses.KEY_END:
                ensure_row(cur_row)
                cur_col = len(grid[cur_row])

            elif key == curses.KEY_PPAGE:
                cur_row = max(0, cur_row - (edit_h - 1))

            elif key == curses.KEY_NPAGE:
                cur_row += edit_h - 1
                ensure_row(cur_row)

            elif key in (curses.KEY_BACKSPACE, 127):
                if cur_col > 0:
                    target = cur_col - 1
                    ensure_row(cur_row)
                    if target < len(grid[cur_row]):
                        grid[cur_row].pop(target)
                    cur_col -= 1
                elif cur_row > 0:
                    cur_row -= 1
                    ensure_row(cur_row)
                    cur_col = len(grid[cur_row])

            elif key == curses.KEY_DC:
                ensure_row(cur_row)
                if cur_col < len(grid[cur_row]):
                    grid[cur_row].pop(cur_col)

            elif key == curses.KEY_ENTER:
                if overwrite:
                    cur_row += 1
                    cur_col = 0
                    ensure_row(cur_row)
                else:
                    ensure_row(cur_row)
                    rest = grid[cur_row][cur_col:]
                    grid[cur_row] = grid[cur_row][:cur_col]
                    grid.insert(cur_row + 1, rest)
                    cur_row += 1
                    cur_col = 0

        # ── Character (string) keys ───────────────────────────────────
        else:
            ch = key  # already a str, may be multi-byte Unicode

            if ch == '\x13':  # Ctrl+S — done
                show_exit_msg(" ^S — done, returning to menu... ")
                break

            elif ch in ('\x18', '\x03'):  # Ctrl+X or Ctrl+C — abort
                show_exit_msg(" ^X — aborted, changes discarded. ")
                aborted = True
                break

            elif ch == '\x0f':  # Ctrl+O — toggle mode
                overwrite = not overwrite

            elif ch == '\x04':  # Ctrl+D — delete current line
                ensure_row(cur_row)
                if len(grid) > 1:
                    grid.pop(cur_row)
                    if cur_row >= len(grid):
                        cur_row = len(grid) - 1
                else:
                    grid[0] = []
                cur_col = min(cur_col, len(grid[cur_row]))

            elif ch in ('\n', '\r'):
                if overwrite:
                    cur_row += 1
                    cur_col = 0
                    ensure_row(cur_row)
                else:
                    ensure_row(cur_row)
                    rest = grid[cur_row][cur_col:]
                    grid[cur_row] = grid[cur_row][:cur_col]
                    grid.insert(cur_row + 1, rest)
                    cur_row += 1
                    cur_col = 0

            elif ch == '\x7f' or ch == '\x08':  # Backspace (some terminals)
                if cur_col > 0:
                    target = cur_col - 1
                    ensure_row(cur_row)
                    if target < len(grid[cur_row]):
                        grid[cur_row].pop(target)
                    cur_col -= 1
                elif cur_row > 0:
                    cur_row -= 1
                    ensure_row(cur_row)
                    cur_col = len(grid[cur_row])

            elif ord(ch) >= 32:  # Any printable character, including all Unicode
                ensure_row(cur_row)
                if overwrite:
                    pad_to_col(cur_row, cur_col + 1)
                    grid[cur_row][cur_col] = ch
                else:
                    pad_to_col(cur_row, cur_col)
                    grid[cur_row].insert(cur_col, ch)
                cur_col += 1

    if aborted:
        return None

    result_lines = ["".join(row) for row in grid]
    return "\n".join(result_lines)


def edit_frame(existing=""):
    """Launch curses editor; return new content string or None to abort."""
    result = curses.wrapper(_curses_edit, existing)
    return result



def check_frame_whitespace(frame):
    """After editing a frame, prompt to strip trailing whitespace if present. Returns the frame."""
    lines = frame.split("\n")
    has_trailing_spaces = any(l != l.rstrip() for l in lines)
    trailing_blank_lines = len(lines) - len("\n".join(lines).rstrip("\n").split("\n"))
    if has_trailing_spaces or trailing_blank_lines > 0:
        print("\n  This frame has trailing spaces or blank lines at the end.")
        print("  Is this intentional?")
        ans = input("  Keep? (y=keep / n=strip) [y]: ").strip().lower()
        if ans == "n":
            lines = [l.rstrip() for l in lines]
            while lines and lines[-1] == "":
                lines.pop()
            frame = "\n".join(lines)
            print("  Stripped.")
    return frame


def frame_summary(frame, max_width=60):
    first_nonempty = next(
        (l for l in frame.split("\n") if l.strip() and not l.strip().startswith(TRANSITION_MARKER)),
        "(empty)",
    )
    s = first_nonempty[:max_width]
    return s + ("…" if len(first_nonempty) > max_width else "")


def get_transition(frames):
    if not frames:
        return None
    for line in reversed(frames[-1].split("\n")):
        if line.strip().startswith(TRANSITION_MARKER):
            return line.strip()[len(TRANSITION_MARKER):]
    return None


def set_transition(frames, trigger):
    if not frames:
        return
    lines = [l for l in frames[-1].split("\n") if not l.strip().startswith(TRANSITION_MARKER)]
    if trigger:
        lines.append(f"{TRANSITION_MARKER}{trigger}")
    frames[-1] = "\n".join(lines)


def main():
    clear()
    print("╔══════════════════════════════╗")
    print("║  terminalFiction  EDITOR     ║")
    print("╚══════════════════════════════╝\n")

    print(f"  Save directory: {DEFAULT_SAVE_DIR}")
    filename = input("  Filename (new or existing, no path needed): ").strip()
    if not filename:
        print("  No filename given. Exiting.")
        return
    if not filename.endswith(".txt"):
        filename += ".txt"
    filepath = os.path.join(DEFAULT_SAVE_DIR, filename)
    print(f"  → {filepath}")

    frames = []
    if os.path.exists(filepath):
        frames = read_file(filepath)
        print(f"  Loaded {len(frames)} frame(s).")
    else:
        print("  (New file — starting empty.)")

    dirty = False

    while True:
        trigger = get_transition(frames)
        print(f"\n  [{filepath}]  {len(frames)} frame(s)  transition: {trigger or '(none)'}")
        print("  ─────────────────────────────────────────")
        print("  1  List frames")
        print("  2  Edit frame")
        print("  3  Add new frame")
        print("  4  Delete frame")
        print("  5  Reorder frames (move frame)")
        print("  6  Preview animation")
        print("  7  Set/clear transition trigger")
        print("  8  Save")
        print("  9  Save & quit")
        print("  0  Quit (discard unsaved changes)")

        choice = input("\n  > ").strip()

        if choice == "1":
            clear()
            if not frames:
                print("  (No frames yet.)")
            for i, f in enumerate(frames):
                marker = " [has transition]" if i == len(frames) - 1 and trigger else ""
                print(f"  Frame {i+1:2d}: {frame_summary(f)}{marker}")

        elif choice == "2":
            if not frames:
                print("  No frames to edit.")
                continue
            try:
                idx = int(input(f"  Frame number to edit (1–{len(frames)}): ")) - 1
            except ValueError:
                continue
            if not (0 <= idx < len(frames)):
                print("  Out of range.")
                continue
            result = edit_frame(frames[idx])
            if result is not None:
                frames[idx] = check_frame_whitespace(result)
                dirty = True
                print("  Frame updated.")

        elif choice == "3":
            result = edit_frame()
            if result is not None:
                frames.append(check_frame_whitespace(result))
                dirty = True
                print(f"  Frame added. Total: {len(frames)}")

        elif choice == "4":
            if not frames:
                print("  No frames to delete.")
                continue
            try:
                idx = int(input(f"  Frame number to delete (1–{len(frames)}): ")) - 1
            except ValueError:
                continue
            if not (0 <= idx < len(frames)):
                print("  Out of range.")
                continue
            confirm = input(f"  Delete frame {idx+1}? (y/n): ").strip().lower()
            if confirm == "y":
                frames.pop(idx)
                dirty = True
                print("  Deleted.")

        elif choice == "5":
            if len(frames) < 2:
                print("  Need at least 2 frames to reorder.")
                continue
            try:
                src = int(input(f"  Move frame number (1–{len(frames)}): ")) - 1
                dst = int(input(f"  To position (1–{len(frames)}): ")) - 1
            except ValueError:
                continue
            if not (0 <= src < len(frames) and 0 <= dst < len(frames)):
                print("  Out of range.")
                continue
            frame = frames.pop(src)
            frames.insert(dst, frame)
            dirty = True
            print(f"  Moved frame {src+1} to position {dst+1}.")

        elif choice == "6":
            if not frames:
                print("  No frames to preview.")
                continue
            try:
                fps_str = input("  FPS (default 2): ").strip()
                fps = float(fps_str) if fps_str else 2.0
            except ValueError:
                fps = 2.0
            preview(frames, fps)

        elif choice == "7":
            current = get_transition(frames)
            print(f"  Current trigger: {current or '(none)'}")
            print("  Enter trigger word (e.g. 'continue', 'open', 'enter'), or leave blank to clear:")
            trigger_input = input("  > ").strip()
            set_transition(frames, trigger_input or None)
            dirty = True
            if trigger_input:
                print(f"  Transition set → —type:{trigger_input}")
            else:
                print("  Transition cleared.")

        elif choice == "8":
            write_file(filepath, frames)
            dirty = False
            print(f"  Saved: {filepath}")

        elif choice == "9":
            write_file(filepath, frames)
            print(f"  Saved: {filepath}  Goodbye.")
            break

        elif choice == "0":
            if dirty:
                confirm = input("  Unsaved changes. Quit anyway? (y/n): ").strip().lower()
                if confirm != "y":
                    continue
            break


if __name__ == "__main__":
    main()
