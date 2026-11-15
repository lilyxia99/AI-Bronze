# terminalFiction — 完整操作指南

## 目录

1. [文件结构](#1-文件结构)
2. [编辑器 editor.py](#2-编辑器-editorpy)
3. [播放器 player.py](#3-播放器-playerpy)
4. [主运行器 main_runner.py](#4-主运行器-main_runnerpy)
5. [过场效果 transition.py](#5-过场效果-transitionpy)
6. [特殊脚本 .py 场景](#6-特殊脚本-py-场景)
7. [从头搭建一个互动故事](#7-从头搭建一个互动故事)

---

## 1. 文件结构

```
program/terminalFiction/
  editor.py          ← 帧编辑器（制作 .txt 动画文件）
  player.py          ← 单文件播放器（预览一个 .txt）
  main_runner.py     ← 主运行器（串联整个故事）
  transition.py      ← 内置过场效果库
  examples/
    main.txt         ← 示例故事脚本
    intro.txt        ← 示例场景
    station.txt      ← 示例多帧动画
    message.txt
    choice.py        ← 示例交互脚本
    credits.txt

Assets/              ← 你用编辑器保存的 .txt 文件默认存这里
  your_scene.txt
  ...
```

---

## 2. 编辑器 editor.py

### 启动

```bash
python3 editor.py
```

输入文件名，无需路径，无需 `.txt` 后缀，自动补全。文件保存到 `DEFAULT_SAVE_DIR`（见文件顶部常量，可修改）。

### 主菜单

| 按键 | 操作 |
|------|------|
| `1` | 列出所有帧 |
| `2` | 编辑指定帧 |
| `3` | 新增一帧 |
| `4` | 删除指定帧 |
| `5` | 调整帧顺序 |
| `6` | 预览动画 |
| `7` | 设置 / 清除过场触发词 |
| `8` | 保存 |
| `9` | 保存并退出 |
| `0` | 退出 |

### 帧编辑器（全屏）

| 按键 | 效果 |
|------|------|
| ← ↑ → ↓ | 移动光标 |
| Home / End | 行首 / 行尾 |
| Page Up / Page Down | 翻页 |
| Enter | 光标移到下一行行首（打字机风格） |
| 任意可见字符 | 当前模式下输入，光标右移 |
| **Ctrl+O** | 切换 **Overwrite**（覆盖）/ **Insert**（插入）模式 |
| Backspace | 删除光标左侧字符，右边内容左移 |
| Delete | 删除光标处字符，右边内容左移 |
| Ctrl+K | 删除当前整行 |
| **Ctrl+S** | 保存，不离开编辑器 |
| **Ctrl+D** | 完成编辑，返回主菜单 |
| **Ctrl+X** | 放弃本次编辑，返回主菜单 |

完成编辑后若该帧有行尾空格或末尾空行，会询问是否清除。

### 过场触发词（主菜单选项 7）

在最后一帧附加一个 `—type:单词` 标记，告诉播放器等待玩家输入哪个词才推进故事。例如：

```
—type:investigate
```

这行在预览和播放时不显示，只被运行器读取。

---

## 3. 播放器 player.py

用于**单独预览**一个 `.txt` 动画文件，无故事逻辑，默认循环播放。

```bash
# 循环播放，默认 2 fps
python3 player.py Assets/my_scene.txt

# 指定帧率
python3 player.py Assets/my_scene.txt 4

# 只播放一次
python3 player.py Assets/my_scene.txt 2 --once
```

Ctrl+C 停止。

---

## 4. 主运行器 main_runner.py

运行一个完整的互动故事。

```bash
# 运行指定故事脚本
python3 main_runner.py path/to/main.txt

# 指定帧率（默认 2）
python3 main_runner.py path/to/main.txt 3

# 运行内置示例
python3 main_runner.py
```

### main.txt 格式

故事脚本是一个纯文本文件，用 `→` 把场景串联起来：

```
# 这是注释
scene1.txt → scene2.txt → scene3.txt → credits.txt
```

路径相对于 `main.txt` 所在文件夹。

**附加过场效果**：在 `.txt` 文件名后用 `-` 接一个 `.py` 过场脚本：

```
intro.txt → station.txt-static_glitch.py → message.txt → choice.py → credits.txt
```

意思是：`station.txt` 播放完后，用 `static_glitch.py` 作为过场效果，再进入 `message.txt`。

**使用内置效果**（无需写 py 文件）：用 `builtin:效果名` 语法暂不支持直接在 main.txt 里写，需要在自定义过场脚本里调用（见下文）。

### 运行流程

1. 按顺序读取 `main.txt` 里的每一项
2. `.txt` 场景：播放所有帧，停在最后一帧
3. 读取最后一帧的 `—type:触发词`，等玩家输入
4. 玩家输入正确触发词后，执行过场效果，进入下一场景
5. `.py` 脚本：直接调用其 `run()` 函数
6. 所有场景结束后显示 END 画面

---

## 5. 过场效果 transition.py

### 内置效果

| 名称 | 描述 |
|------|------|
| `default` | 等待触发词，然后清屏 |
| `dissolve` | 当前画面字符随机替换为下一画面 |
| `glitch` | 短暂乱码闪烁后清屏 |
| `wipe` | 从上到下逐行滑入下一画面 |
| `typewriter` | 清屏后逐字打出下一画面 |

**单独测试某个效果**：

```bash
python3 transition.py glitch
python3 transition.py dissolve
python3 transition.py wipe
```

### 自定义过场脚本

新建一个 `.py` 文件，定义 `run()` 函数：

```python
# my_transition.py
import time, sys

def run(trigger=None, current="", next_content=""):
    # trigger      — 玩家刚输入的触发词（可忽略）
    # current      — 当前场景的文本内容（可用于效果）
    # next_content — 下一场景第一帧的文本内容（可用于效果）

    # 例：先调用内置效果，再做额外处理
    import transition as T
    T.glitch(trigger=trigger, current=current, next_content=next_content)
    time.sleep(0.5)
```

然后在 `main.txt` 里引用：

```
scene1.txt-my_transition.py → scene2.txt
```

---

## 6. 特殊脚本 .py 场景

当你需要**分支选择**或**纯代码交互**时，用 `.py` 场景代替 `.txt`。

```python
# my_choice.py

def run():
    print("  你来到了一个岔路口。")
    print("  [left] 走向森林")
    print("  [right] 走向城镇")
    print()

    choice = ""
    while choice not in ("left", "right"):
        choice = input("  > ").strip().lower()

    if choice == "left":
        # 可以直接在这里播放另一个场景，或设置全局状态
        print("  你走进了森林...")
    else:
        print("  你走向了城镇...")
```

在 `main.txt` 里像普通场景一样放入：

```
intro.txt → my_choice.py → epilogue.txt
```

> `.py` 场景之后**不等待触发词**，`run()` 返回后直接进入下一项。

---

## 7. 从头搭建一个互动故事

### 步骤

**1. 用编辑器制作场景**

```bash
python3 editor.py
```

- 输入文件名，例如 `forest`（自动保存为 `Assets/forest.txt`）
- 用帧编辑器画 ASCII 画面，多帧则自动成为动画
- 在最后一帧设置触发词（主菜单 `7`），例如 `enter`
- 保存退出

**2. 创建 main.txt**

在你的故事文件夹里新建 `main.txt`（可以和 `.txt` 场景放在同一目录）：

```
# 我的故事

Assets/intro.txt → Assets/forest.txt-builtin_glitch.py → Assets/cave.txt
```

或者把场景文件和 `main.txt` 都放在同一个文件夹里，直接用文件名：

```
intro.txt → forest.txt → cave.txt
```

**3. 运行故事**

```bash
python3 program/terminalFiction/main_runner.py path/to/main.txt
```

### 最简单的例子

```
Assets/
  story/
    main.txt      ← 故事脚本
    scene1.txt    ← 有 —type:go 触发词
    scene2.txt    ← 最后一个场景，无触发词
```

`main.txt` 内容：

```
scene1.txt → scene2.txt
```

`scene1.txt` 最后一帧末尾（用编辑器选项 7 设置）：

```
—type:go
```

运行后：玩家看完 `scene1` 的动画，输入 `go`，过场清屏，进入 `scene2`。

---

## 快速参考

```
制作场景     python3 program/terminalFiction/editor.py
单独预览     python3 program/terminalFiction/player.py Assets/xxx.txt
运行故事     python3 program/terminalFiction/main_runner.py path/to/main.txt
测试过场     python3 program/terminalFiction/transition.py glitch
```

修改默认保存目录：打开 `editor.py` 顶部，修改 `DEFAULT_SAVE_DIR`。
