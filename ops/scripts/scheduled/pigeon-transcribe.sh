#!/bin/bash
# Pigeon Transcription
# Pulls recordings from Google Drive, appends transcripts to voice.md
# Uses on-device transcriptions (.md companion files) when available, falls back to hear
# Runs on a schedule via launchd — set up by setup-pigeon.sh.
# Config at ~/.pigeon/config (workspace path).

# Time guard: only run 7am–midnight (skip overnight if scheduled 24/7)
hour=$(date +%H)
if [ "$hour" -lt 7 ]; then
    exit 0
fi

CONFIG_FILE="$HOME/.pigeon/config"
PIGEON_DIR="$HOME/Sync/pigeon"
DRIVE_AUDIO="gdrive:pigeon/audio"
DRIVE_TRANSCRIPTS="gdrive:pigeon/transcripts"

# Load workspace path
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: no config at $CONFIG_FILE"
    echo "Run setup-pigeon.sh first"
    exit 1
fi
source "$CONFIG_FILE"

if [ -z "$WORKSPACE" ] || [ ! -d "$WORKSPACE" ]; then
    echo "Error: workspace not found at $WORKSPACE"
    exit 1
fi

VOICE_DIR="$WORKSPACE/.voice"
DOWNLOADED_FILE="$VOICE_DIR/pigeon-downloaded"
PROCESSED_FILE="$VOICE_DIR/pigeon-processed"
VOICE_MD="$WORKSPACE/voice.md"

mkdir -p "$VOICE_DIR"

# Find tools (optional — hear only needed as fallback)
HEAR_PATH=$(which hear 2>/dev/null || echo "$HOME/.local/bin/hear")
RCLONE_PATH=$(which rclone 2>/dev/null || echo "$HOME/.local/bin/rclone")

mkdir -p "$PIGEON_DIR"
touch "$DOWNLOADED_FILE"
touch "$PROCESSED_FILE"

# Step 1: Pull new files from Google Drive
if [ -f "$RCLONE_PATH" ] && "$RCLONE_PATH" listremotes 2>/dev/null | grep -q "^gdrive:"; then
    echo "Checking Google Drive for new recordings..."

    # Phase 1a: Pull transcripts first (on-device transcription)
    "$RCLONE_PATH" lsf "$DRIVE_TRANSCRIPTS" --include "*.md" 2>/dev/null | while read md_file; do
        audio_file="${md_file%.md}.m4a"
        if ! grep -Fxq "$audio_file" "$DOWNLOADED_FILE" 2>/dev/null; then
            echo "Downloading transcript: $md_file"
            "$RCLONE_PATH" copy "$DRIVE_TRANSCRIPTS/$md_file" "$PIGEON_DIR/"
            echo "$audio_file" >> "$DOWNLOADED_FILE"
        fi
    done

    # Phase 1b: Pull audio files that don't have transcripts
    TRANSCRIPT_LIST=$(mktemp)
    "$RCLONE_PATH" lsf "$DRIVE_TRANSCRIPTS" --include "*.md" 2>/dev/null > "$TRANSCRIPT_LIST"

    "$RCLONE_PATH" lsf "$DRIVE_AUDIO" --include "*.m4a" 2>/dev/null | while read filename; do
        if grep -Fxq "$filename" "$DOWNLOADED_FILE" 2>/dev/null; then
            continue
        fi

        # Check if transcript exists (already downloaded in Phase 1a)
        md_file="${filename%.md}.md"
        if grep -Fxq "$md_file" "$TRANSCRIPT_LIST" 2>/dev/null; then
            continue
        fi

        echo "Downloading audio: $filename"
        "$RCLONE_PATH" copy "$DRIVE_AUDIO/$filename" "$PIGEON_DIR/"
        echo "$filename" >> "$DOWNLOADED_FILE"
    done

    rm -f "$TRANSCRIPT_LIST"
else
    echo "rclone not configured — skipping Drive pull"
fi

# Step 2: Process new files locally
new_count=0

# Phase 2a: Process transcripts first
while IFS= read -r -d '' md_file; do
    filename=$(basename "${md_file%.md}.m4a")

    date_id=$(echo "$filename" | grep -oE '[0-9]{8}_[0-9]{6}' || echo "")
    if [ -n "$date_id" ] && grep -q "$date_id" "$PROCESSED_FILE" 2>/dev/null; then
        continue
    fi

    echo "Using on-device transcript: $filename"
    # Strip pigeon-id comment and header from iOS app output
    transcript=$(grep -v '<!-- pigeon-id:' "$md_file" | sed '/^## Pigeon -/d')

    # Detect broken transcripts: repeated phrases indicate looping bug
    if echo "$transcript" | grep -qE '(.{20,})\1{2,}'; then
        echo "Transcript broken (repetition detected): $filename"
        continue
    elif [ ${#transcript} -lt 10 ]; then
        echo "Transcript too short: $filename"
        continue
    fi

    # Parse date from filename: pigeon_YYYYMMDD_HHMMSS.m4a
    date_part=$(echo "$filename" | grep -oE '[0-9]{8}_[0-9]{6}' || echo "")
    if [ -n "$date_part" ]; then
        created="${date_part:0:4}-${date_part:4:2}-${date_part:6:2} ${date_part:9:2}:${date_part:11:2}"
    else
        created=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$md_file")
    fi

    {
        echo ""
        echo "## Pigeon - $created"
        echo ""
        echo "$transcript"
        echo ""
    } >> "$VOICE_MD"

    echo "$filename" >> "$PROCESSED_FILE"
    ((new_count++))
done < <(find "$PIGEON_DIR" -name "*.md" -print0 2>/dev/null)

# Phase 2b: Process audio files without transcripts (fallback to hear)
while IFS= read -r -d '' memo; do
    filename=$(basename "$memo")

    date_id=$(echo "$filename" | grep -oE '[0-9]{8}_[0-9]{6}' || echo "")
    if [ -n "$date_id" ] && grep -q "$date_id" "$PROCESSED_FILE" 2>/dev/null; then
        continue
    fi

    # Check if transcript exists (would have been processed in Phase 2a)
    md_file="$PIGEON_DIR/${filename%.m4a}.md"
    if [ -f "$md_file" ]; then
        continue
    fi

    # No transcript, need to transcribe with hear
    if [ -f "$HEAR_PATH" ]; then
        echo "Transcribing with hear: $filename"
        transcript=$("$HEAR_PATH" -d -i "$memo" 2>/dev/null || echo "[transcription failed]")
    else
        echo "Skipping $filename — no transcript and hear not installed"
        continue
    fi

    # Parse date from filename: pigeon_YYYYMMDD_HHMMSS.m4a
    date_part=$(echo "$filename" | grep -oE '[0-9]{8}_[0-9]{6}' || echo "")
    if [ -n "$date_part" ]; then
        created="${date_part:0:4}-${date_part:4:2}-${date_part:6:2} ${date_part:9:2}:${date_part:11:2}"
    else
        created=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$memo")
    fi

    {
        echo ""
        echo "## Pigeon - $created"
        echo ""
        echo "$transcript"
        echo ""
    } >> "$VOICE_MD"

    echo "$filename" >> "$PROCESSED_FILE"
    ((new_count++))
done < <(find "$PIGEON_DIR" -name "*.m4a" -print0 2>/dev/null)

if [ $new_count -gt 0 ]; then
    echo "Processed $new_count new memo(s)"
else
    echo "No new memos to process"
fi
