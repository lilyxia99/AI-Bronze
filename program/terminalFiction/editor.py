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
DEFAULT_SAVE_DIR = os.path.normpath(os.path.join(_SCRIPT_DIR, "..", "..", "Assets","asciiart"))
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


def _curses_edit(stdscr, frames, start_index, save_callback):
    """Edit a frame sequence. Onion-skin cells are display-only overlays."""
    curses.use_default_colors()
    # raw() lets Ctrl+S reach us instead of being swallowed by terminal flow control.
    # We handle Ctrl+C manually as abort since raw() disables SIGINT.
    curses.raw()
    try:
        curses.curs_set(1)
    except curses.error:
        pass

    # Line-number gutter color: best-effort guess of dark/light terminal
    # background via COLORFGBG (many terminals set it); falls back to a
    # plain dim attribute when it can't be determined or colors aren't available.
    num_attr = curses.A_DIM
    try:
        if curses.has_colors():
            # Onion-skin references. COLOR_RED/COLOR_CYAN remain readable on
            # both common dark and light terminal themes when dimmed below.
            curses.init_pair(2, curses.COLOR_RED, -1)
            curses.init_pair(3, curses.COLOR_CYAN, -1)
            colorfgbg = os.environ.get("COLORFGBG", "")
            bg = None
            if ";" in colorfgbg:
                try:
                    bg = int(colorfgbg.split(";")[-1])
                except ValueError:
                    bg = None
            if bg in (0, 8):
                curses.init_pair(1, curses.COLOR_GREEN, -1)
                num_attr = curses.color_pair(1) | curses.A_DIM
            elif bg in (7, 15):
                curses.init_pair(1, curses.COLOR_BLACK, -1)
                num_attr = curses.color_pair(1) | curses.A_DIM
    except curses.error:
        pass

    frame_index = start_index
    grid = []
    cur_row = 0
    cur_col = 0
    scroll_top = 0
    overwrite = True  # Start in Overwrite mode; Ctrl+O toggles to Insert mode
    cursor_stays = False  # Ctrl+F toggles: keep cursor in place after typing a char
    onion_enabled = False  # Ctrl+G
    onion_range = 1        # Ctrl+W / Ctrl+E

    def load_frame(index):
        nonlocal grid, cur_row, cur_col, scroll_top
        raw_lines = frames[index].split("\n") if frames[index] else [""]
        grid = [list(line) for line in raw_lines]
        cur_row = cur_col = scroll_top = 0

    def commit_frame():
        frames[frame_index] = "\n".join("".join(row) for row in grid)

    def ghost_at(row, col):
        """Return ghost character and color pair for an otherwise blank cell."""
        if not onion_enabled:
            return None
        # Previous frames are light red; following frames are light blue.
        # Nearest frame wins, so the reference is easy to read.
        for distance in range(1, onion_range + 1):
            previous = frame_index - distance
            if previous >= 0:
                lines = frames[previous].split("\n")
                if row < len(lines) and col < len(lines[row]) and lines[row][col] != " ":
                    return lines[row][col], 2
            following = frame_index + distance
            if following < len(frames):
                lines = frames[following].split("\n")
                if row < len(lines) and col < len(lines[row]) and lines[row][col] != " ":
                    return lines[row][col], 3
        return None

    load_frame(frame_index)

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

        # Draw grid rows, overlaying line numbers on each row's leading
        # blank run (purely visual — never written into the grid).
        num_width = len(str(len(grid))) if grid else 1
        for sy in range(edit_h):
            gy = sy + scroll_top
            row = grid[gy] if gy < len(grid) else []
            full_str = "".join(row)

            avail = 0
            for c in range(num_width):
                if c < len(row):
                    if row[c] == ' ':
                        avail += 1
                    else:
                        break
                else:
                    avail += 1  # past end of row counts as implicit blank

            shown = str(gy + 1).rjust(num_width)[num_width - avail:] if avail else ""

            try:
                if shown:
                    shown_disp = shown[:w - 1]
                    stdscr.addstr(sy, 0, shown_disp, num_attr)
                    rest = full_str[avail:][:max(0, w - 1 - len(shown_disp))]
                    if rest:
                        stdscr.addstr(sy, len(shown_disp), rest)
                else:
                    stdscr.addstr(sy, 0, full_str[:w - 1])
            except curses.error:
                pass

            # Draw references only in blank cells. They never modify ``grid``;
            # typing at their position therefore naturally replaces the overlay.
            if onion_enabled:
                for gx in range(w - 1):
                    if gx < len(row) and row[gx] != " ":
                        continue
                    ghost = ghost_at(gy, gx)
                    if ghost:
                        try:
                            stdscr.addstr(sy, gx, ghost[0], curses.color_pair(ghost[1]) | curses.A_DIM)
                        except curses.error:
                            pass

        # Status bar
        sy_status = h - STATUS_LINES
        mode_label = "Overwrite" if overwrite else "Insert"
        cursor_label = "Cursor:Fixed" if cursor_stays else "Cursor:Advance"
        hint = (
            f" Frame {frame_index+1}/{len(frames)}  Ln {cur_row+1} Col {cur_col+1}"
            f"  │  {mode_label}  ^O=toggle  {cursor_label}  ^F=toggle"
            f"  Onion:{'on' if onion_enabled else 'off'}({onion_range}) ^G ^W/^E"
            f"  ^P/^N=frame  ^S=save  ^D=done  ^X=discard frame"
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

            elif key == curses.KEY_BTAB:  # Shift+Tab — shift every line left by one space
                for r in range(len(grid)):
                    if grid[r]:
                        grid[r].pop(0)
                if cur_col > 0:
                    cur_col -= 1

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

            if ch == '\x13':  # Ctrl+S — save without leaving the editor
                commit_frame()
                try:
                    save_callback()
                    show_exit_msg(" ^S — saved. ")
                except OSError as exc:
                    show_exit_msg(f" Save failed: {exc} ")

            elif ch == '\x04':  # Ctrl+D — done
                commit_frame()
                show_exit_msg(" ^D — returning to menu... ")
                break

            elif ch in ('\x18', '\x03'):  # Ctrl+X or Ctrl+C — discard current frame edits
                load_frame(frame_index)
                show_exit_msg(" ^X — current frame restored. ")

            elif ch == '\x0f':  # Ctrl+O — toggle mode
                overwrite = not overwrite

            elif ch == '\x06':  # Ctrl+F — toggle cursor-stays-in-place after typing
                cursor_stays = not cursor_stays

            elif ch == '\x07':  # Ctrl+G — toggle onion skin
                onion_enabled = not onion_enabled

            elif ch == '\x17':  # Ctrl+W — show fewer reference frames
                onion_range = max(1, onion_range - 1)

            elif ch == '\x05':  # Ctrl+E — show more reference frames
                onion_range = min(max(1, len(frames) - 1), onion_range + 1)

            elif ch == '\x10':  # Ctrl+P — previous frame
                if frame_index > 0:
                    commit_frame()
                    frame_index -= 1
                    load_frame(frame_index)

            elif ch == '\x0e':  # Ctrl+N — next frame
                if frame_index < len(frames) - 1:
                    commit_frame()
                    frame_index += 1
                    load_frame(frame_index)

            elif ch == '\t':  # Tab — shift every line in the frame right by one space
                for r in range(len(grid)):
                    grid[r].insert(0, ' ')
                cur_col += 1

            elif ch == '\x0b':  # Ctrl+K — delete current line
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
                if not cursor_stays:
                    cur_col += 1

    return frame_index


def edit_frame_sequence(frames, start_index, save_callback):
    """Launch the multi-frame curses editor and return its final frame index."""
    return curses.wrapper(_curses_edit, frames, start_index, save_callback)



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
    saved_snapshot = frames.copy()

    def save_from_editor():
        """Write the current in-memory sequence without leaving curses."""
        nonlocal dirty
        write_file(filepath, frames)
        saved_snapshot[:] = frames
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
            edit_frame_sequence(frames, idx, save_from_editor)
            dirty = frames != saved_snapshot
            print("  Returned from frame editor.")

        elif choice == "3":
            if frames:
                try:
                    after = int(input(f"  Create after frame (0–{len(frames)}; 0 = beginning): "))
                except ValueError:
                    continue
                if not (0 <= after <= len(frames)):
                    print("  Out of range.")
                    continue
            else:
                after = 0
            frames.insert(after, "")
            dirty = True
            edit_frame_sequence(frames, after, save_from_editor)
            dirty = frames != saved_snapshot
            print(f"  Frame inserted at position {after+1}. Total: {len(frames)}")

        elif choice == "4":
            if not frames:
                print("  No frames to delete.")
                continue
            try:
                idx = int(input(f"  Delete which frame (1–{len(frames)}): ")) - 1
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
            saved_snapshot[:] = frames
            print(f"  Saved: {filepath}")

        elif choice == "9":
            write_file(filepath, frames)
            saved_snapshot[:] = frames
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
