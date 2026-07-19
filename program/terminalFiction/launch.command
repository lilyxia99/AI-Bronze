#!/bin/bash
# terminalFiction Launcher
# Double-click this file on macOS to open Terminal and start the story.
# The file must remain in the same folder as main_runner.py.

cd "$(dirname "$0")"

# Check Python 3 is available
if ! command -v python3 &>/dev/null; then
  echo "Python 3 is required but not found. Please install it from python.org"
  read -p "Press Enter to exit..."
  exit 1
fi

python3 main_runner.py examples/main.txt

# Keep terminal open after story ends
echo ""
read -p "Press Enter to close this window..."
