#!/bin/bash
# Automated voice note processing
# Routes transcribed voice notes to the right places in the workspace
# Runs on schedule via launchd — no human input required

# Find workspace root (parent of ops/)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE="$(cd "$SCRIPT_DIR/../../.." && pwd)"
cd "$WORKSPACE"

LAST_RUN=".voice/last-auto-run"

# Check if voice.md has any content at all
if [ ! -s voice.md ]; then
    echo "No voice entries to process"
    exit 0
fi

# Skip if voice.md hasn't been modified since last successful run
# This is format-agnostic — works with any entry style (headers, dates, plain text)
if [ -f "$LAST_RUN" ] && [ ! voice.md -nt "$LAST_RUN" ]; then
    echo "voice.md unchanged since last run"
    exit 0
fi

# Find claude binary
CLAUDE=$(which claude 2>/dev/null || echo "$HOME/.local/bin/claude")
if [ ! -f "$CLAUDE" ]; then
    echo "Claude CLI not found"
    exit 1
fi

# Snapshot voice.md timestamp to detect if Claude modified it
VOICE_TIME_BEFORE=$(stat -f "%m" voice.md 2>/dev/null || echo "0")

# Run Claude with timeout — a hung process blocks launchd from re-running the job
TMPOUT=$(mktemp)
$CLAUDE -p "/voice" --max-turns 25 --dangerously-skip-permissions >"$TMPOUT" 2>&1 &
CLAUDE_PID=$!

# Kill after 10 minutes
( sleep 600; kill $CLAUDE_PID 2>/dev/null ) &
TIMER_PID=$!

wait $CLAUDE_PID
EXIT_CODE=$?
kill $TIMER_PID 2>/dev/null

OUTPUT=$(cat "$TMPOUT")
rm -f "$TMPOUT"

if [ $EXIT_CODE -eq 137 ] || [ $EXIT_CODE -eq 143 ]; then
    echo "Voice processing timed out after 10 minutes"
    exit 1
fi

if [ $EXIT_CODE -ne 0 ]; then
    echo "Voice processing failed (exit code $EXIT_CODE)"
    echo "$OUTPUT" | grep -i "error\|fail\|401\|403\|timeout" | head -3
    exit 1
fi

# Claude exited 0. Check if it actually did work.
VOICE_TIME_AFTER=$(stat -f "%m" voice.md 2>/dev/null || echo "0")

if [ "$VOICE_TIME_BEFORE" = "$VOICE_TIME_AFTER" ]; then
    # voice.md wasn't modified — check if there were routable entries
    ROUTABLE=$(grep -cE "^## (Pigeon|Vault|Memo) " voice.md 2>/dev/null || echo "0")
    if [ "$ROUTABLE" -eq 0 ]; then
        # Only needs-context or unroutable entries — nothing for headless Claude to do
        echo "Only needs-context entries, skipping"
    else
        echo "Routable entries exist but Claude didn't process them"
        exit 1
    fi
fi

# Mark successful run — next time we'll skip unless voice.md is modified again
mkdir -p .voice
touch "$LAST_RUN"

echo "Voice routing complete"
