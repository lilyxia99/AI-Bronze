# terminalFiction 编辑器鼠标支持 — 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 curses 帧编辑器加鼠标支持——普通模式点击移动光标，画笔模式（Ctrl+P）点击/拖动盖章 + 调色板换笔，并正确处理中文宽字符的坐标换算。

**Architecture:** 全部改动集中在 `program/terminalFiction/editor.py`。新增 4 个模块级纯函数处理屏幕列↔grid 下标换算（可单测），`_curses_edit()` 主循环里加鼠标事件分支和画笔状态。零新依赖（仅标准库 `unicodedata`）。

**Tech Stack:** Python 3 标准库（curses、unicodedata、unittest）。

**Spec:** `docs/superpowers/specs/2026-06-10-editor-mouse-support-design.md`

**注意：本项目不是 git 仓库（Obsidian iCloud 目录），所有 commit 步骤省略。**

**注意：Task 3/4 的交互行为需要真实终端里人工操作验证，agent 只做编译检查和单元测试；人工验收集中在 Task 5 由用户执行。**

---

## 文件结构

| 文件 | 动作 | 职责 |
|---|---|---|
| `program/terminalFiction/editor.py` | 修改 | 加坐标换算纯函数 + 鼠标事件处理 + 画笔模式 |
| `program/terminalFiction/test_editor.py` | 新建 | 坐标换算函数的 unittest |

---

### Task 1: 宽字符坐标换算纯函数（TDD）

**Files:**
- Modify: `program/terminalFiction/editor.py`（模块顶部，`FRAME_SEP` 定义附近）
- Create: `program/terminalFiction/test_editor.py`

- [ ] **Step 1: 写失败的测试**

新建 `program/terminalFiction/test_editor.py`，完整内容：

```python
#!/usr/bin/env python3
"""Tests for the coordinate helpers in editor.py.

Run from this directory:  python3 -m unittest test_editor -v
"""
import unittest

from editor import char_width, str_width, grid_col_to_screen_x, screen_x_to_grid_col


class TestCharWidth(unittest.TestCase):
    def test_ascii_is_one(self):
        self.assertEqual(char_width("A"), 1)
        self.assertEqual(char_width(" "), 1)

    def test_cjk_is_two(self):
        self.assertEqual(char_width("商"), 2)
        self.assertEqual(char_width("，"), 2)  # fullwidth comma

    def test_block_chars_are_one(self):
        # ░▒▓█·─│ are East Asian Ambiguous → width 1,
        # matching default rendering in macOS terminals.
        for ch in "█▓▒░·─│":
            self.assertEqual(char_width(ch), 1)


class TestStrWidth(unittest.TestCase):
    def test_mixed_string(self):
        self.assertEqual(str_width("A商B"), 4)  # 1 + 2 + 1


class TestGridColToScreenX(unittest.TestCase):
    def test_ascii(self):
        row = list("hello")
        self.assertEqual(grid_col_to_screen_x(row, 0), 0)
        self.assertEqual(grid_col_to_screen_x(row, 3), 3)

    def test_pure_cjk(self):
        row = list("商朝")
        self.assertEqual(grid_col_to_screen_x(row, 1), 2)
        self.assertEqual(grid_col_to_screen_x(row, 2), 4)

    def test_mixed(self):
        row = list("A商B")  # screen: A=0, 商=1..2, B=3
        self.assertEqual(grid_col_to_screen_x(row, 1), 1)
        self.assertEqual(grid_col_to_screen_x(row, 2), 3)

    def test_past_end_counts_single_width(self):
        row = list("商")  # width 2
        self.assertEqual(grid_col_to_screen_x(row, 3), 4)  # 2 + 2 padding cols


class TestScreenXToGridCol(unittest.TestCase):
    def test_ascii(self):
        row = list("hello")
        self.assertEqual(screen_x_to_grid_col(row, 0), 0)
        self.assertEqual(screen_x_to_grid_col(row, 4), 4)

    def test_right_half_of_wide_char_selects_it(self):
        row = list("商朝")
        self.assertEqual(screen_x_to_grid_col(row, 0), 0)
        self.assertEqual(screen_x_to_grid_col(row, 1), 0)  # right half of 商
        self.assertEqual(screen_x_to_grid_col(row, 2), 1)
        self.assertEqual(screen_x_to_grid_col(row, 3), 1)  # right half of 朝

    def test_mixed(self):
        row = list("A商B")
        self.assertEqual(screen_x_to_grid_col(row, 0), 0)
        self.assertEqual(screen_x_to_grid_col(row, 1), 1)
        self.assertEqual(screen_x_to_grid_col(row, 2), 1)
        self.assertEqual(screen_x_to_grid_col(row, 3), 2)

    def test_click_past_end(self):
        row = list("ab")
        self.assertEqual(screen_x_to_grid_col(row, 5), 5)

    def test_click_past_end_after_cjk(self):
        row = list("商")
        self.assertEqual(screen_x_to_grid_col(row, 2), 1)
        self.assertEqual(screen_x_to_grid_col(row, 4), 3)


class TestRoundTrip(unittest.TestCase):
    def test_grid_to_screen_to_grid(self):
        row = list(" 在3000多年前")
        for col in range(len(row) + 3):
            x = grid_col_to_screen_x(row, col)
            self.assertEqual(screen_x_to_grid_col(row, x), col)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd "/Users/lilyxia99_mac_mini/Library/Mobile Documents/iCloud~md~obsidian/Documents/NextCloud-digital-palace/WIP/AI Bronze/program/terminalFiction" && python3 -m unittest test_editor -v
```

预期：`ImportError: cannot import name 'char_width' from 'editor'`

- [ ] **Step 3: 实现四个函数**

在 `editor.py` 顶部 import 区加：

```python
import unicodedata
```

在 `TRANSITION_MARKER = "—type:"` 之后、`DEFAULT_SAVE_DIR` 之前加：

```python
def char_width(ch):
    """Terminal display width of one character: 2 for fullwidth/wide (CJK), else 1."""
    return 2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1


def str_width(s):
    """Terminal display width of a string."""
    return sum(char_width(ch) for ch in s)


def grid_col_to_screen_x(row_chars, col):
    """Screen column where the grid cell at index `col` starts.

    Columns past the end of the row count 1 screen cell each
    (padding is always spaces).
    """
    x = str_width("".join(row_chars[:col]))
    if col > len(row_chars):
        x += col - len(row_chars)
    return x


def screen_x_to_grid_col(row_chars, screen_x):
    """Grid index targeted by a click at screen column `screen_x`.

    Clicking either half of a wide character targets that character.
    Clicks past the end of the row map to virtual padded columns.
    """
    x = 0
    for i, ch in enumerate(row_chars):
        w = char_width(ch)
        if screen_x < x + w:
            return i
        x += w
    return len(row_chars) + (screen_x - x)
```

- [ ] **Step 4: 跑测试确认全部通过**

```bash
cd "/Users/lilyxia99_mac_mini/Library/Mobile Documents/iCloud~md~obsidian/Documents/NextCloud-digital-palace/WIP/AI Bronze/program/terminalFiction" && python3 -m unittest test_editor -v
```

预期：全部 PASS（OK，14 个测试）。

---

### Task 2: 修复光标显示位置（中文行偏移 bug）

**Files:**
- Modify: `program/terminalFiction/editor.py`（`_curses_edit` 内 "Position cursor" 块，约 134-141 行）

- [ ] **Step 1: 修改光标定位代码**

把：

```python
        # Position cursor
        screen_cur_y = cur_row - scroll_top
        screen_cur_x = min(cur_col, w - 2)
```

改成：

```python
        # Position cursor
        screen_cur_y = cur_row - scroll_top
        cur_line = grid[cur_row] if cur_row < len(grid) else []
        screen_cur_x = min(grid_col_to_screen_x(cur_line, cur_col), w - 2)
```

- [ ] **Step 2: 验证**

```bash
cd "/Users/lilyxia99_mac_mini/Library/Mobile Documents/iCloud~md~obsidian/Documents/NextCloud-digital-palace/WIP/AI Bronze/program/terminalFiction" && python3 -c "import editor; print('OK')" && python3 -m unittest test_editor -v
```

预期：`OK` + 测试全 PASS。（光标视觉效果在 Task 5 人工验收。）

---

### Task 3: 启用鼠标 + 普通模式点击移动光标

**Files:**
- Modify: `program/terminalFiction/editor.py`（`_curses_edit` 开头、状态变量区、int-key 分支链、`edit_frame`）

- [ ] **Step 1: 开启鼠标事件**

`_curses_edit` 中，把：

```python
    curses.raw()
```

改成：

```python
    curses.raw()
    # Mouse: clicks always work; REPORT_MOUSE_POSITION + xterm 1003 mode
    # additionally enables drag events on terminals that report motion
    # (e.g. iTerm2). Terminals without mouse support just never send
    # KEY_MOUSE — keyboard-only editing is unaffected.
    curses.mouseinterval(0)
    curses.mousemask(curses.ALL_MOUSE_EVENTS | curses.REPORT_MOUSE_POSITION)
    sys.stdout.write("\033[?1003h")
    sys.stdout.flush()
```

- [ ] **Step 2: 加 mouse_down 状态变量**

把：

```python
    overwrite = True  # Start in Overwrite mode; Ctrl+O toggles to Insert mode
```

改成：

```python
    overwrite = True  # Start in Overwrite mode; Ctrl+O toggles to Insert mode
    mouse_down = False  # Left button held (for drag detection)
```

- [ ] **Step 3: 加 KEY_MOUSE 分支**

在 int-key 分支链的 `elif key == curses.KEY_ENTER:` 块**之后**（即整个 `if isinstance(key, int):` 链的末尾）加：

```python
            elif key == curses.KEY_MOUSE:
                try:
                    _id, mx, my, _z, bstate = curses.getmouse()
                except curses.error:
                    continue

                press = bool(bstate & (curses.BUTTON1_PRESSED | curses.BUTTON1_CLICKED))
                if bstate & curses.BUTTON1_PRESSED:
                    mouse_down = True
                if bstate & (curses.BUTTON1_RELEASED | curses.BUTTON1_CLICKED):
                    mouse_down = False

                if press and my < edit_h:
                    gy = my + scroll_top
                    ensure_row(gy)
                    cur_row = gy
                    cur_col = screen_x_to_grid_col(grid[gy], mx)
```

- [ ] **Step 4: 退出时关闭 motion 报告模式**

把 `edit_frame` 整个函数：

```python
def edit_frame(existing=""):
    """Launch curses editor; return new content string or None to abort."""
    result = curses.wrapper(_curses_edit, existing)
    return result
```

改成：

```python
def edit_frame(existing=""):
    """Launch curses editor; return new content string or None to abort."""
    try:
        result = curses.wrapper(_curses_edit, existing)
    finally:
        # Turn off the xterm motion-reporting mode enabled in _curses_edit,
        # so the shell doesn't receive mouse escape sequences after exit.
        sys.stdout.write("\033[?1003l")
        sys.stdout.flush()
    return result
```

- [ ] **Step 5: 验证**

```bash
cd "/Users/lilyxia99_mac_mini/Library/Mobile Documents/iCloud~md~obsidian/Documents/NextCloud-digital-palace/WIP/AI Bronze/program/terminalFiction" && python3 -c "import editor; print('OK')" && python3 -m unittest test_editor -v
```

预期：`OK` + 测试全 PASS。（点击行为在 Task 5 人工验收。）

---

### Task 4: 画笔模式 + 调色板

**Files:**
- Modify: `program/terminalFiction/editor.py`（模块常量区、`_curses_edit` 状态区、状态栏绘制、KEY_MOUSE 分支、字符键分支）

- [ ] **Step 1: 加调色板常量**

在 `TRANSITION_MARKER = "—type:"` 之后加：

```python
# Brush characters shown in the paint-mode palette (space = eraser)
PAINT_PALETTE = ["█", "▓", "▒", "░", "·", "─", "│", " "]
```

- [ ] **Step 2: 加画笔状态变量**

把（Task 3 改过的）：

```python
    mouse_down = False  # Left button held (for drag detection)
```

改成：

```python
    mouse_down = False  # Left button held (for drag detection)
    paint_mode = False  # Ctrl+P toggles; mouse stamps `brush` instead of moving cursor
    brush = "█"
```

- [ ] **Step 3: 状态栏显示画笔与调色板**

把状态栏块：

```python
        # Status bar
        sy_status = h - STATUS_LINES
        mode_label = "Overwrite" if overwrite else "Insert"
        hint = (
            f" Ln {cur_row+1} Col {cur_col+1}"
            f"  │  {mode_label}  ^O=toggle  ^S=done  ^X=abort  ^D=del-line"
        )
```

改成：

```python
        # Status bar
        sy_status = h - STATUS_LINES
        mode_label = "Overwrite" if overwrite else "Insert"
        palette_spans = []  # (screen_x_start, screen_x_end, brush_char) per palette entry
        if paint_mode:
            brush_label = "␣" if brush == " " else brush
            hint = f" PAINT [{brush_label}]  "
            x = str_width(hint)
            for pch in PAINT_PALETTE:
                label = "␣" if pch == " " else pch
                hint += label + " "
                palette_spans.append((x, x + char_width(label), pch))
                x += char_width(label) + 1
            hint += " │ click=stamp  type=brush  ^P=cursor"
        else:
            hint = (
                f" Ln {cur_row+1} Col {cur_col+1}"
                f"  │  {mode_label}  ^O=toggle  ^P=paint  ^S=done  ^X=abort  ^D=del-line"
            )
```

- [ ] **Step 4: KEY_MOUSE 分支换成完整版（盖章 + 拖动 + 调色板）**

把 Task 3 加的整个 `elif key == curses.KEY_MOUSE:` 块替换为：

```python
            elif key == curses.KEY_MOUSE:
                try:
                    _id, mx, my, _z, bstate = curses.getmouse()
                except curses.error:
                    continue

                press = bool(bstate & (curses.BUTTON1_PRESSED | curses.BUTTON1_CLICKED))
                drag = mouse_down and bool(bstate & curses.REPORT_MOUSE_POSITION)
                if bstate & curses.BUTTON1_PRESSED:
                    mouse_down = True
                if bstate & (curses.BUTTON1_RELEASED | curses.BUTTON1_CLICKED):
                    mouse_down = False

                if my < edit_h:
                    gy = my + scroll_top
                    if paint_mode and (press or drag):
                        # Stamp the brush character onto the clicked cell
                        ensure_row(gy)
                        gx = screen_x_to_grid_col(grid[gy], mx)
                        pad_to_col(gy, gx + 1)
                        grid[gy][gx] = brush
                        cur_row, cur_col = gy, gx
                    elif press:
                        ensure_row(gy)
                        cur_row = gy
                        cur_col = screen_x_to_grid_col(grid[gy], mx)
                elif paint_mode and press and my == h - 1:
                    # Click on the hint line: palette hit test
                    for x0, x1, pch in palette_spans:
                        if x0 <= mx < x1:
                            brush = pch
                            break
```

- [ ] **Step 5: Ctrl+P 切换 + 打字换笔**

字符键分支链中，在 `elif ch == '\x0f':  # Ctrl+O — toggle mode` 块之后加：

```python
            elif ch == '\x10':  # Ctrl+P — toggle paint mode
                paint_mode = not paint_mode
```

把可打印字符分支的开头：

```python
            elif ord(ch) >= 32:  # Any printable character, including all Unicode
                ensure_row(cur_row)
```

改成：

```python
            elif ord(ch) >= 32:  # Any printable character, including all Unicode
                if paint_mode:
                    brush = ch  # Typing in paint mode picks the brush, doesn't write
                    continue
                ensure_row(cur_row)
```

- [ ] **Step 6: 验证**

```bash
cd "/Users/lilyxia99_mac_mini/Library/Mobile Documents/iCloud~md~obsidian/Documents/NextCloud-digital-palace/WIP/AI Bronze/program/terminalFiction" && python3 -c "import editor; print('OK')" && python3 -m unittest test_editor -v
```

预期：`OK` + 测试全 PASS。

---

### Task 5: 人工验收（用户在真实终端执行）

**Files:** 无代码改动。测试文件用 `Assets/mousetest.txt`（结束后删除）。

- [ ] **Step 1: 启动编辑器**

```bash
cd "/Users/lilyxia99_mac_mini/Library/Mobile Documents/iCloud~md~obsidian/Documents/NextCloud-digital-palace/WIP/AI Bronze/program/terminalFiction" && python3 editor.py
```

文件名输入 `mousetest`，选 `3` 新建帧。
（macOS 自带 Terminal 需先 View > Allow Mouse Reporting / ⌘R；iTerm2 无需设置。）

- [ ] **Step 2: 普通模式验收**

先打几行字（混些中文，如 `商朝 test ▓▓`），然后：
- 点击任意位置 → 状态栏 Ln/Col 跟着变，光标落点正确；
- 点击汉字的左半/右半 → 光标都落在该汉字上；
- 键盘方向键在中文行上移动 → 光标视觉位置与字符对齐（Task 2 修复的效果）。

- [ ] **Step 3: 画笔模式验收**

按 `^P`：
- 状态栏变为 `PAINT [█]` + 调色板；
- 点击画面 → 盖上 █；按住拖动（iTerm2）→ 连续作画；
- 点调色板里的 `░` → 画笔变 ░，再点画面盖的是 ░；
- 键盘打 `商` → 画笔变 商，点击盖出汉字；
- 点调色板 `␣` → 空格擦除之前画的字符；
- 再按 `^P` → 回普通模式，打字恢复正常输入。

- [ ] **Step 4: 保存与播放一致性验收**

`^S` 退出编辑，菜单选 `9` 保存退出，然后：

```bash
cd "/Users/lilyxia99_mac_mini/Library/Mobile Documents/iCloud~md~obsidian/Documents/NextCloud-digital-palace/WIP/AI Bronze/program/terminalFiction" && python3 player.py "../../Assets/mousetest.txt" 2 --once
```

预期：播放画面与编辑器内所见逐列一致（同一终端、同一字体）。

- [ ] **Step 5: 回归检查**

- 退出编辑器后在 shell 里移动鼠标 → 不出现乱码转义序列（1003 模式已关闭）；
- 纯键盘流程（^O/^S/^X/^D、方向键、退格）不受影响。

- [ ] **Step 6: 清理**

```bash
rm "/Users/lilyxia99_mac_mini/Library/Mobile Documents/iCloud~md~obsidian/Documents/NextCloud-digital-palace/WIP/AI Bronze/Assets/mousetest.txt"
```
