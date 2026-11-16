#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$DIR"

# Build if needed
if [ ! -d "build/DayBook AI.app" ]; then
    ./scripts/build.sh
fi

echo "🚀 Launching DayBook AI..."
open "build/DayBook AI.app"
echo "DayBook AI is running! Check your macOS Dock or application windows."
