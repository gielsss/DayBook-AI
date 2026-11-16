#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$DIR"

# Build executable first
./scripts/build.sh

echo ""
echo "Running automated verification tests..."
"./build/DayBook AI.app/Contents/MacOS/DayBookAI" --test-persistence
