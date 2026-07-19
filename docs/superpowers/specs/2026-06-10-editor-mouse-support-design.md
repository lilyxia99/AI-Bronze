# terminalFiction 编辑器鼠标支持 — 设计文档

日期：2026-06-10
状态：已确认（方案 A）

## 目标

给 `program/terminalFiction/editor.py` 的 curses 帧编辑器加鼠标支持，让用户可以用鼠标点击画面直接编辑 ASCII/中文混排的场景图。

核心前提：**编辑时看到的画面必须和播放器（player.py / main_runner.py）在终端里的显示完全一致。** 因此编辑器继续运行在终端 curses 里（与播放共用同一字体与宽度规则），不引入网页或 TUI 框架模拟。

## 交互设计

### 普通模式（默认，现有行为不变）

- 鼠标左键点击编辑区任意位置 → 光标跳到该格子，之后键盘输入照旧。
- 所有现有快捷键保留：`^O` 切换覆盖/插入、`^S` 完成、`^X` 放弃、`^D` 删行。

### 画笔模式（新增，`Ctrl+P` 切换）

- 左键点击编辑区 → 把"当前画笔字符"盖到该格子。
- 按住左键拖动 → 沿途连续盖章（终端支持鼠标移动报告时生效，见兼容性）。
- 键盘输入任何可打印字符（含中文）→ 不写入画面，而是把它设为当前画笔。
- 空格也是合法画笔，用于擦除。
- 再按 `Ctrl+P` 返回普通模式。

### 调色板

- 画笔模式下，状态栏提示行显示常用画笔：`█ ▓ ▒ ░ · ─ │ ␣`（␣ 代表空格）。
- 鼠标点击提示行上的某个调色板字符 → 设为当前画笔。
- 状态栏始终显示当前模式与画笔，如 `Paint [█]`。

## 技术方案

改动集中在 `editor.py` 的 `_curses_edit()`，零新依赖。

1. **启用鼠标**：
   - `curses.mousemask(curses.ALL_MOUSE_EVENTS | curses.REPORT_MOUSE_POSITION)`
   - `curses.mouseinterval(0)`（点击立即响应，不等待双击判定）
2. **事件处理**：`get_wch()` 返回 `curses.KEY_MOUSE` 时调 `curses.getmouse()` 取 `(id, mx, my, z, bstate)`：
   - `my < edit_h`（编辑区内）：`gy = my + scroll_top`，`gx = screen_x_to_grid_col(grid[gy], mx)`。普通模式移动光标；画笔模式 `pad_to_col` 后盖章。
   - 画笔模式且点击落在状态栏提示行：按预先记录的调色板字符屏幕 x 区间命中测试，命中即换笔。
   - 拖动：`REPORT_MOUSE_POSITION` 事件且左键按住时，视同点击盖章。
3. **新增状态**：`paint_mode: bool`（默认 False）、`brush: str`（默认 `"█"`）。`Ctrl+P` = `'\x10'`。

### 关键点：中文宽字符坐标换算

画面是中英混排，一个汉字屏幕上占 2 列、grid 里占 1 个元素，屏幕坐标和 grid 下标不一一对应。新增两个纯函数（用 `unicodedata.east_asian_width`，`'W'`/`'F'` 计宽 2，其余计 1）：

- `screen_x_to_grid_col(row_chars, screen_x) -> int`：鼠标点击换算。点在宽字符右半边时归属该字符。
- `grid_col_to_screen_x(row_chars, col) -> int`：反向换算。

**顺带修复现有 bug**：当前代码用 grid 下标直接当屏幕列定位光标（`stdscr.move(screen_cur_y, screen_cur_x)`），行内有中文时光标显示位置偏移。改用 `grid_col_to_screen_x` 定位，键盘编辑中文行时光标也会变准。

### 边界情况

- 点击超出行尾：普通模式光标可停在行尾外（现有 `pad_to_col` 逻辑打字时补空格）；画笔模式先补空格再盖章。
- 宽字符画笔（如汉字）盖进一个 grid 格子，渲染占 2 列、会把行内后续字符向右推 1 列——符合 grid 模型，接受。
- 调色板点击只在画笔模式下生效；普通模式点状态栏不做任何事。

## 兼容性

- 终端不支持鼠标：`mousemask` 返回 0，编辑器静默退回纯键盘操作，无报错。
- iTerm2：点击 + 拖动全支持。
- macOS 自带 Terminal：需开启 View > Allow Mouse Reporting（⌘R）；拖动报告视版本而定，最差退化为逐点点击。
- 鼠标模式由 curses 在 `endwin()` 时自动还原，不污染退出后的终端。

## 测试

- **单元测试**：`screen_x_to_grid_col` / `grid_col_to_screen_x` 是纯函数，新建 `program/terminalFiction/test_editor.py` 覆盖：纯 ASCII 行、纯中文行、中英混排行、点击宽字符右半边、超出行尾。
- **手动验收清单**：
  1. 普通模式点击移动光标（含中文行）；
  2. `^P` 进入画笔模式，点击盖章、打字换笔、点调色板换笔、空格擦除；
  3. iTerm2 拖动连续作画；
  4. 编辑后用 `player.py` 播放，画面与编辑器内所见一致；
  5. 关闭鼠标报告的终端里键盘流程不受影响。

## 不做的事（YAGNI）

- 不做矩形选区、复制粘贴、撤销。
- 不做悬停高亮、右键菜单。
- 不改 player.py / main_runner.py / 帧格式。
