#!/usr/bin/env python3
import sys
import os
import time
import requests

ASSETS = os.path.join(os.path.dirname(__file__), "..", "Assets")
NORMAL_ART = os.path.join(ASSETS, "BronzeAsciiArt-normal.txt")
SMOKE_ART = os.path.join(ASSETS, "BronzeAsciiArt-smoke.txt")

DEEPSEEK_API_KEY = "sk-43d94d4d8ccd43b9925dc0b2b8975d7a"
DEEPSEEK_URL = "https://api.deepseek.com/chat/completions"

SYSTEM_PROMPT = (
    "你是一尊商周青铜器中的神灵，以商周卜辞的语气回答问卜者的问题。"
    "用古奥简短的文言，如卜辞体裁：先述日期或兆象，再述吉凶占断，最后或附一句神谕。"
    "每次回答不超过五十字。不使用现代标点，只用句读或无标点。"
)


def read_art(path: str) -> list[str]:
    with open(path, encoding="utf-8") as f:
        return f.read().splitlines()


def art_height(lines: list[str]) -> int:
    return len(lines)


def display_art(lines: list[str]) -> None:
    for line in lines:
        print(line)


def replace_art_in_place(old_lines: list[str], new_lines: list[str]) -> None:
    """Overwrite previously printed art lines using ANSI cursor-up."""
    # Move cursor up by the number of old lines
    sys.stdout.write(f"\033[{len(old_lines)}A")
    sys.stdout.write("\033[J")  # clear from cursor to end of screen
    # Pad new art to at least the same height so nothing bleeds through
    padded = list(new_lines)
    while len(padded) < len(old_lines):
        padded.append("")
    for line in padded:
        print(line)


def ask_oracle(question: str) -> str:
    payload = {
        "model": "deepseek-chat",
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": question},
        ],
        "max_tokens": 120,
    }
    headers = {
        "Authorization": f"Bearer {DEEPSEEK_API_KEY}",
        "Content-Type": "application/json",
    }
    try:
        resp = requests.post(DEEPSEEK_URL, json=payload, headers=headers, timeout=30)
        resp.raise_for_status()
        return resp.json()["choices"][0]["message"]["content"].strip()
    except Exception as e:
        return f"【神谕不至，兆象不明：{e}】"


def typewrite(text: str, delay: float = 0.05) -> None:
    for ch in text:
        sys.stdout.write(ch)
        sys.stdout.flush()
        time.sleep(delay)
    print()


def main() -> None:
    normal_lines = read_art(NORMAL_ART)
    smoke_lines = read_art(SMOKE_ART)

    print()
    display_art(normal_lines)
    print()
    print("（输入「人」以问卜，输入「退」以离去）")

    current_lines = normal_lines
    smoke_active = False

    while True:
        try:
            cmd = input("\n> ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\n问卜已毕。")
            break

        if cmd == "退":
            print("神灵归寂。")
            break

        if cmd == "人" and not smoke_active:
            # Animate smoke appearing
            print()  # blank line before art for spacing
            # Move up past the blank line + the art + blank line + prompt line
            # We printed: blank, art(N lines), blank, prompt — so art is 2+N+1 lines back
            # Simpler: just reprint from scratch using replace
            # We need to account for what's on screen since display_art
            # Let's reprint cleanly by clearing the art block
            # Count lines printed after the art: blank + hint line + blank + "> 人" line = 4
            extra = 4  # blank after art, hint, blank before input, input line itself
            sys.stdout.write(f"\033[{len(current_lines) + extra}A")
            sys.stdout.write("\033[J")
            print()
            display_art(smoke_lines)
            current_lines = smoke_lines
            smoke_active = True
            print()
            print("祭火已燃，神灵降临。")
            print("汝欲问何事？")
            continue

        if smoke_active:
            if not cmd:
                continue
            print("\n占曰……")
            time.sleep(0.8)
            answer = ask_oracle(cmd)
            print()
            typewrite(answer)
            print()
            print("（可继续问卜，或输入「退」离去）")
        else:
            print("（请先输入「人」以召唤神灵）")


if __name__ == "__main__":
    main()
