#!/bin/bash
# Setup Pigeon Pipeline
# Run from your workspace, or pass the workspace path as an argument.
# Works via curl: bash <(curl -sL URL) ~/path/to/workspace
#
# Flags:
#   --on-device, -d   Install 'hear' for on-device transcription
#
# What it does:
# 1. Installs rclone (no Homebrew, no sudo)
# 2. Connects your Google Drive
# 3. Downloads the transcription script
# 4. Schedules transcription every hour via launchd
#
# After setup, recordings from Pigeon on your phone are
# automatically transcribed and appended to voice.md.

set -e

PIGEON_HOME="$HOME/.pigeon"
RCLONE_DIR="$HOME/.local/bin"
PIGEON_DIR="$HOME/Sync/pigeon"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.pigeon.transcribe"
SETUP_URL="https://raw.githubusercontent.com/derek-larson14/delegate/main/ops/scripts/setup-pigeon.sh"
TRANSCRIBE_URL="https://raw.githubusercontent.com/derek-larson14/delegate/main/ops/scripts/pigeon-transcribe.sh"

# Parse flags
ON_DEVICE=false
POSITIONAL_ARGS=()
for arg in "$@"; do
    case $arg in
        --on-device|-d)
            ON_DEVICE=true
            ;;
        *)
            POSITIONAL_ARGS+=("$arg")
            ;;
    esac
done

echo "=== Pigeon Pipeline Setup ==="
echo ""

# Detect workspace path
if [ ${#POSITIONAL_ARGS[@]} -gt 0 ]; then
    WORKSPACE="$(cd "${POSITIONAL_ARGS[0]}" && pwd)"
elif [ -f "CLAUDE.md" ]; then
    WORKSPACE="$PWD"
else
    echo "[!] Run this from your workspace folder (the one with CLAUDE.md)."
    echo "    cd ~/Downloads/claude-workspace && curl -sL $SETUP_URL | bash"
    exit 1
fi

if [ ! -f "$WORKSPACE/CLAUDE.md" ]; then
    echo "[!] No CLAUDE.md found in $WORKSPACE"
    echo "    Download the workspace first: delegatewithclaude.com/commands"
    exit 1
fi

echo "[ok] Workspace: $WORKSPACE"

# Save config
mkdir -p "$PIGEON_HOME"
echo "WORKSPACE=$WORKSPACE" > "$PIGEON_HOME/config"

# Step 1: Find or install rclone
RCLONE_PATH=$(which rclone 2>/dev/null || true)
if [ -n "$RCLONE_PATH" ]; then
    echo "[ok] rclone found at $RCLONE_PATH"
elif [ -f "$RCLONE_DIR/rclone" ]; then
    RCLONE_PATH="$RCLONE_DIR/rclone"
    echo "[ok] rclone found at $RCLONE_PATH"
else
    echo "[*] Installing rclone..."
    mkdir -p "$RCLONE_DIR"

    TMPDIR=$(mktemp -d)
    ARCH=$(uname -m)
    if [ "$ARCH" = "arm64" ]; then
        RCLONE_ARCH="osx-arm64"
    else
        RCLONE_ARCH="osx-amd64"
    fi

    curl -sL "https://downloads.rclone.org/rclone-current-${RCLONE_ARCH}.zip" -o "$TMPDIR/rclone.zip"
    unzip -q "$TMPDIR/rclone.zip" -d "$TMPDIR"
    cp "$TMPDIR"/rclone-*/rclone "$RCLONE_DIR/rclone"
    chmod +x "$RCLONE_DIR/rclone"
    rm -rf "$TMPDIR"

    RCLONE_PATH="$RCLONE_DIR/rclone"
    echo "[ok] rclone installed to $RCLONE_PATH"
fi

# Step 2: Configure Google Drive remote
if "$RCLONE_PATH" listremotes 2>/dev/null | grep -q "^gdrive:"; then
    echo "[ok] gdrive remote already configured"
else
    echo ""
    echo "[*] Connecting Google Drive..."
    echo "    A browser window will open. Sign in with your Google account."
    echo ""
    "$RCLONE_PATH" config create gdrive drive
    echo ""
    echo "[ok] Google Drive connected"
fi

# Step 3: Test connection
echo ""
echo "[*] Testing Google Drive connection..."
if "$RCLONE_PATH" lsd gdrive: 2>/dev/null | head -3; then
    echo "[ok] Drive connection working"
else
    echo "[!] Could not list Drive contents — check with: $RCLONE_PATH config"
fi

if "$RCLONE_PATH" lsd gdrive:pigeon 2>/dev/null; then
    echo "[ok] pigeon/ folder found on Drive"
    if "$RCLONE_PATH" lsd gdrive:pigeon/audio 2>/dev/null; then
        echo "[ok] pigeon/audio/ subfolder found"
    else
        echo "[*] pigeon/audio/ subfolder not found — it appears after your first recording"
    fi
    if "$RCLONE_PATH" lsd gdrive:pigeon/transcripts 2>/dev/null; then
        echo "[ok] pigeon/transcripts/ subfolder found"
    else
        echo "[*] pigeon/transcripts/ subfolder not found — it appears after your first transcription"
    fi
else
    echo "[*] pigeon/ folder not on Drive yet — it appears after your first recording"
fi

# Step 4: Create local directories
mkdir -p "$PIGEON_DIR"
echo "[ok] Local pigeon directory: $PIGEON_DIR"

# Step 5: Check hear installation (auto-install with --on-device flag)
HEAR_PATH=$(which hear 2>/dev/null || echo "$HOME/.local/bin/hear")
if [ -f "$HEAR_PATH" ]; then
    echo "[ok] hear found at $HEAR_PATH"
elif [ "$ON_DEVICE" = true ]; then
    echo ""
    echo "[*] Installing hear (on-device speech recognition)..."
    mkdir -p "$HOME/.local/bin"

    HEAR_TMP=$(mktemp -d)
    curl -sL "https://sveinbjorn.org/files/software/hear.zip" -o "$HEAR_TMP/hear.zip"

    if [ ! -s "$HEAR_TMP/hear.zip" ]; then
        echo "[!] Failed to download hear"
        echo "    Install manually from https://sveinbjorn.org/hear"
        rm -rf "$HEAR_TMP"
    else
        unzip -o "$HEAR_TMP/hear.zip" -d "$HEAR_TMP/hear"
        HEAR_BIN=$(find "$HEAR_TMP/hear" -name "hear" -type f | head -1)
        if [ -n "$HEAR_BIN" ]; then
            cp "$HEAR_BIN" "$HOME/.local/bin/hear"
            chmod +x "$HOME/.local/bin/hear"
            HEAR_PATH="$HOME/.local/bin/hear"
            echo "[ok] hear installed to $HEAR_PATH"
        else
            echo "[!] Could not find hear binary in downloaded archive"
            echo "    Install manually from https://sveinbjorn.org/hear"
        fi
        rm -rf "$HEAR_TMP"
    fi
else
    echo ""
    echo "[!] hear (Apple speech recognition) not installed"
    echo "    Re-run with --on-device to auto-install:"
    echo "    bash setup-pigeon.sh --on-device"
    echo "    Or run /setup-transcription in Claude Code"
fi

# Step 6: Download transcription script
echo ""
echo "[*] Downloading transcription script..."
curl -sL "$TRANSCRIBE_URL" -o "$PIGEON_HOME/pigeon-transcribe.sh"
chmod +x "$PIGEON_HOME/pigeon-transcribe.sh"
echo "[ok] Saved to $PIGEON_HOME/pigeon-transcribe.sh"

# Step 7: Create and load launchd job
PLIST_PATH="$PLIST_DIR/$PLIST_NAME.plist"

# Unload existing if present
launchctl list "$PLIST_NAME" 2>/dev/null && launchctl unload "$PLIST_PATH" 2>/dev/null || true

mkdir -p "$PLIST_DIR"
cat > "$PLIST_PATH" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$PLIST_NAME</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$PIGEON_HOME/pigeon-transcribe.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartCalendarInterval</key>
    <array>
        <dict><key>Hour</key><integer>8</integer><key>Minute</key><integer>0</integer></dict>
        <dict><key>Hour</key><integer>9</integer><key>Minute</key><integer>0</integer></dict>
        <dict><key>Hour</key><integer>10</integer><key>Minute</key><integer>0</integer></dict>
        <dict><key>Hour</key><integer>11</integer><key>Minute</key><integer>0</integer></dict>
        <dict><key>Hour</key><integer>12</integer><key>Minute</key><integer>0</integer></dict>
        <dict><key>Hour</key><integer>13</integer><key>Minute</key><integer>0</integer></dict>
        <dict><key>Hour</key><integer>14</integer><key>Minute</key><integer>0</integer></dict>
        <dict><key>Hour</key><integer>15</integer><key>Minute</key><integer>0</integer></dict>
        <dict><key>Hour</key><integer>16</integer><key>Minute</key><integer>0</integer></dict>
        <dict><key>Hour</key><integer>17</integer><key>Minute</key><integer>0</integer></dict>
        <dict><key>Hour</key><integer>18</integer><key>Minute</key><integer>0</integer></dict>
        <dict><key>Hour</key><integer>19</integer><key>Minute</key><integer>0</integer></dict>
        <dict><key>Hour</key><integer>20</integer><key>Minute</key><integer>0</integer></dict>
        <dict><key>Hour</key><integer>21</integer><key>Minute</key><integer>0</integer></dict>
        <dict><key>Hour</key><integer>22</integer><key>Minute</key><integer>0</integer></dict>
        <dict><key>Hour</key><integer>23</integer><key>Minute</key><integer>0</integer></dict>
        <dict><key>Hour</key><integer>0</integer><key>Minute</key><integer>0</integer></dict>
    </array>
    <key>StandardOutPath</key>
    <string>$PIGEON_HOME/transcribe.log</string>
    <key>StandardErrorPath</key>
    <string>$PIGEON_HOME/transcribe.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.local/bin</string>
        <key>HOME</key>
        <string>$HOME</string>
    </dict>
</dict>
</plist>
PLIST

launchctl load "$PLIST_PATH"
echo "[ok] Scheduled transcription every hour (8am–midnight)"

echo ""
echo "=== Setup Complete ==="
echo ""
echo "How it works:"
echo "  1. Record on your phone with Pigeon"
echo "  2. Recordings upload to Google Drive"
echo "  3. Every hour, your Mac pulls and transcribes them"
echo "  4. Transcriptions appear in $WORKSPACE/voice.md"
echo ""
echo "Run /voice in Claude Code to route transcripts to tasks and notes."
