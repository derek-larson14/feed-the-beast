---
description: Set up automatic transcription — iPhone Voice Memos or Google Drive (Pigeon)
model: sonnet
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, AskUserQuestion
---

# Voice Transcription

Transcribe voice recordings and add them to voice.md. Supports two sources: iPhone Voice Memos (via iCloud, Mac only) and Google Drive (via Pigeon app, all platforms).

## Step 0: Detect OS

```bash
uname -s 2>/dev/null || echo "Windows"
```

If the output contains "MINGW", "CYGWIN", "MSYS", or "Windows", this is a **Windows** environment. On Windows:
- Voice Memos source is **not available** (iCloud/Voice Memos are Mac-only)
- Auto-set source to "drive" (skip the source question)
- Use PowerShell scripts (.ps1) instead of bash (.sh)
- Use Task Scheduler instead of launchd
- No local `hear` transcription — uses companion `.md` transcripts from Apps Script or Pigeon on-device

## Step 1: Determine source

Check if source is already configured:
```bash
mkdir -p .voice && ([ -f .voice/source ] && cat .voice/source || echo "NOT_SET")
```

**If Windows**: auto-set to "drive" without asking:
```bash
mkdir -p .voice && echo "drive" > .voice/source
```
Tell user: "On Windows, voice transcription uses Google Drive (Pigeon app). Voice Memos is Mac-only."

**If macOS and "NOT_SET"**, use AskUserQuestion:

"Where are your voice recordings?"

Options:
- "Voice Memos (iPhone → iCloud → Mac)"
- "Google Drive (Pigeon app)"
- "Local folder (iCloud Drive, Dropbox, or any folder path)"
- "Mac Shortcut (record directly on your Mac)"

**If "Mac Shortcut"**, share this link and set up the folder:

Tell the user: "Install the Pigeon Shortcut: https://www.icloud.com/shortcuts/c323898b57ec44689d670aa5775b0761 — it records audio, transcribes on-device, and saves a transcript. On first run, pick your transcripts folder (default: ~/pigeon/transcripts/)."

```bash
mkdir -p ~/pigeon/transcripts
echo "mac" > .voice/source
echo "$HOME/pigeon/transcripts" > .voice/local-path
```

Then skip to the auto-routing section — no scheduled transcription needed since the Shortcut handles it on demand.

Save their choice:
```bash
echo "voicememos" > .voice/source   # or "drive" or "local"
```

**If "local"**, ask for the folder path:

Use AskUserQuestion: "What's the full path to your recordings folder?"

Options:
- "iCloud Drive (default Voice Memos path)"
- "Dropbox"

If they pick "iCloud Drive", use: `~/Library/Mobile Documents/iCloud~com~apple~VoiceMemos/Documents`
If they pick "Dropbox", ask for their specific subfolder path.
If they pick "Other", ask for the full path.

Save the path:
```bash
echo "/path/to/recordings" > .voice/local-path
```

Then skip to **Source: Local Folder** section below.

---

## Source: Voice Memos (iCloud)

### Setup Checks (run silently, only message user if action needed)

#### 1. Check `hear` tool

```bash
which hear &>/dev/null && echo "READY"
```

**If not ready**, install it:
```bash
curl -sL https://sveinbjorn.org/files/software/hear.zip -o /tmp/hear.zip && \
unzip -o /tmp/hear.zip -d /tmp/hear && \
mkdir -p ~/.local/bin && \
cp /tmp/hear/hear-*/hear ~/.local/bin/ && \
chmod +x ~/.local/bin/hear && \
rm -rf /tmp/hear /tmp/hear.zip
```

Verify: `~/.local/bin/hear --version`

If `which hear` still fails after install, tell user: "Restart your terminal or add ~/.local/bin to your PATH."

#### 2. Check Full Disk Access

Voice Memos are stored in a macOS-protected location (`~/Library/Group Containers/`). The current process (Obsidian or Terminal) needs Full Disk Access for interactive transcription.

Check access:

```bash
ls "$HOME/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings" &>/dev/null && echo "ACCESS OK" || echo "NO ACCESS"
```

**If "NO ACCESS"**, tell user:

"Obsidian (or Terminal) needs Full Disk Access to read Voice Memos. Quick fix:

1. Open System Settings → Privacy & Security → Full Disk Access
2. Click the + button, find Obsidian (or Terminal) in Applications, add it
3. Restart Obsidian (or Terminal)
4. Run /setup-transcription again"

Then stop - don't proceed until they fix this.

#### 3. Check Speech Recognition permission

```bash
osascript -l JavaScript -e '
ObjC.import("Speech");
var status = $.SFSpeechRecognizer.authorizationStatus;
status;
'
```

- Status `0` = Not determined (need to request)
- Status `1` = Denied
- Status `2` = Restricted
- Status `3` = Authorized

**If status is 0 (not determined)**, trigger the permission prompt:
```bash
osascript -l JavaScript -e '
ObjC.import("Speech");
$.SFSpeechRecognizer.requestAuthorization(function(s) {});
'
```

Tell user: "A permission dialog should appear - please approve Speech Recognition access."

Wait a few seconds, then re-check the status. If now `3`, proceed.

**If status is 1 (denied)**, tell user:

"Speech Recognition permission was denied. To fix:
1. Open System Settings → Privacy & Security → Speech Recognition
2. Find Obsidian and toggle it ON (or click + to add it)
3. Run /setup-transcription again"

Then stop.

#### 4. Trigger iCloud download

iCloud "optimizes" storage - voice memos exist in the cloud but aren't downloaded until the app requests them. Open Voice Memos for 10 seconds to trigger download:

```bash
open -g "/System/Applications/VoiceMemos.app"
sleep 10
osascript -e 'tell application "VoiceMemos" to quit' 2>/dev/null || true
```

#### 5. Check iCloud sync

If folder exists but is empty after triggering download, tell user:

"No Voice Memos found. iCloud sync must be enabled for Voice Memos to appear on your Mac. To set this up:

**On iPhone:**
1. Open Settings → [Your Name] → iCloud → Apps Using iCloud → Show All
2. Find Voice Memos and toggle it ON

**On Mac:**
1. Open System Settings → [Your Name] → iCloud → iCloud Drive → Options (or Apps Syncing to iCloud Drive)
2. Make sure Voice Memos is checked

After enabling, record a test memo on your iPhone, wait a minute, then run /setup-transcription again."

#### 6. Check scheduled transcription

Check if the launchd job is set up or previously declined:

```bash
if launchctl list 2>/dev/null | grep -q "com.voicememos.transcribe"; then
    echo "SCHEDULED"
elif [ -f .voice/no-schedule ]; then
    echo "DECLINED"
else
    echo "NOT_SCHEDULED"
fi
```

**If "SCHEDULED" or "DECLINED"**, skip to Processing Flow.

**If "NOT_SCHEDULED"**, offer to set it up:

Ask the user: "Want to set up automatic transcription? It will run every hour (8am–midnight) while your Mac is awake, transcribing new voice memos to voice.md automatically."

Options: "Yes, set it up" / "No, I'll run manually"

**If they say yes**, install the scheduled job:

##### Build VoiceMemoSync.app

macOS blocks `/bin/bash` from reading Voice Memos in scheduled jobs (TCC protection). We create a tiny app wrapper that gets its own Full Disk Access — targeted, not blanket.

```bash
VAULT_PATH="$(pwd)"
SYNC_APP="$HOME/.voicememos/VoiceMemoSync.app"
mkdir -p "$SYNC_APP/Contents/MacOS"

# Create Info.plist
cat > "$SYNC_APP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>sync</string>
    <key>CFBundleIdentifier</key>
    <string>com.voicememos.sync</string>
    <key>CFBundleName</key>
    <string>VoiceMemoSync</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>LSBackgroundOnly</key>
    <true/>
</dict>
</plist>
PLIST

# Compile Swift wrapper (swift is available on all Macs with Xcode CLT)
cat > /tmp/voicememo-sync.swift << 'SWIFT'
import Foundation
let args = Array(CommandLine.arguments.dropFirst())
guard !args.isEmpty else {
    fputs("Usage: sync <script-path>\n", stderr)
    exit(1)
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/bin/bash")
process.arguments = args
try process.run()
process.waitUntilExit()
exit(process.terminationStatus)
SWIFT

swiftc -o "$SYNC_APP/Contents/MacOS/sync" /tmp/voicememo-sync.swift
codesign --sign - --force "$SYNC_APP"
rm /tmp/voicememo-sync.swift
```

If `swiftc` fails, tell user: "Swift compiler not found. Install Xcode Command Line Tools: `xcode-select --install`"

##### Create the launchd plist

```bash
VAULT_PATH="$(pwd)"
SYNC_BIN="$HOME/.voicememos/VoiceMemoSync.app/Contents/MacOS/sync"
cat > ~/Library/LaunchAgents/com.voicememos.transcribe.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.voicememos.transcribe</string>
    <key>ProgramArguments</key>
    <array>
        <string>${SYNC_BIN}</string>
        <string>${VAULT_PATH}/ops/scripts/scheduled/voice-memos-transcribe.sh</string>
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
    <string>/tmp/voicememos-transcribe.out</string>
    <key>StandardErrorPath</key>
    <string>/tmp/voicememos-transcribe.err</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>HOME</key>
        <string>${HOME}</string>
    </dict>
</dict>
</plist>
EOF
```

Make the script executable and load the job:
```bash
chmod +x "$VAULT_PATH/ops/scripts/scheduled/voice-memos-transcribe.sh"
launchctl load ~/Library/LaunchAgents/com.voicememos.transcribe.plist
```

##### Grant Full Disk Access to VoiceMemoSync

Open Full Disk Access settings:
```bash
open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
```

Tell user:

"One last step — grant Full Disk Access to VoiceMemoSync (this is a tiny app we just built, not blanket bash access):

1. In the Full Disk Access window, click **+**
2. Press **Cmd+Shift+G** and type `~/.voicememos/VoiceMemoSync.app`
3. Add it and make sure the toggle is ON

Automatic transcription is now set up. It runs on login and every hour (8am–midnight). Check logs at `/tmp/voicememos-transcribe.out`."

**If they say no**, create a marker so we don't ask again:
```bash
touch .voice/no-schedule
```

### Processing Flow (Voice Memos)

Once setup checks pass:

#### 1. Detect first run vs. ongoing

Check if `.voice/memos-processed` exists and has content:
```bash
if [ -s .voice/memos-processed ]; then echo "ONGOING"; else echo "FIRST_RUN"; fi
```

#### 2. First Run Flow

If first run, show the user what exists and let them choose scope.

**Get memo count and date range:**
```bash
find "$HOME/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings" -maxdepth 1 -name "*.m4a" -type f | wc -l
```

**Use AskUserQuestion** to present options:

"Found [N] voice memos. How far back do you want to transcribe?"

Options:
- "Last 5 memos"
- "Last week"
- "Last month"
- "All of them"

Based on their choice, determine which memos to process.

**Important**: After processing their chosen scope, mark ALL older memos as processed too (so they don't get asked again).

#### 3. Ongoing Run Flow (not first run)

Find memos not yet processed. For each file, check:
```bash
grep -qxF "filename.m4a" .voice/memos-processed || echo "needs processing"
```

If no new memos, tell user "No new voice memos to process." and stop.

#### 4. Transcribe memos

For each memo to process:
```bash
~/.local/bin/hear -d -i "$filepath"
```

The `-d` flag forces on-device recognition (avoids network hangs).

#### 5. Append to voice.md

Extract timestamp from filename (format: `YYYYMMDD HHMMSS*.m4a`) to get human-readable date.

Format:
```markdown
## Memo - Jan 15 at 9:42 AM

[transcription text]

```

Append to `voice.md`.

#### 6. Mark as processed

```bash
echo "$filename" >> .voice/memos-processed
```

#### 7. Summary

Tell user:
- How many memos transcribed
- Remind them: "Run /voice to route these notes to the right places."

---

## Source: Google Drive (Pigeon)

**macOS/Linux:**

Run the pigeon transcription script:

```bash
chmod +x ops/scripts/scheduled/pigeon-transcribe.sh
./ops/scripts/scheduled/pigeon-transcribe.sh
```

This script pulls `.m4a` recordings from Google Drive via rclone, along with companion `.md` transcript files (one per recording, created on-device or by Apps Script). If a companion transcript exists, it uses that; otherwise it falls back to local transcription with `hear`.

If it reports errors about rclone not being configured, help the user set it up:
```bash
# Install rclone and configure Drive
bash ops/scripts/setup-pigeon.sh
```

Or just connect Drive manually:
```bash
rclone config create gdrive drive
```

**Windows:**

Run the PowerShell pigeon transcription script:

```bash
powershell.exe -ExecutionPolicy Bypass -File ops/scripts/scheduled/pigeon-transcribe.ps1
```

This pulls `.m4a` recordings from Google Drive along with companion `.md` transcript files. On Windows, files without a companion `.md` transcript are skipped (no local `hear` tool). To get transcripts, set up one of:
- **Apps Script (Gemini)**: delegatewithclaude.com/voice — cloud transcription, creates companion `.md` files in gdrive:pigeon
- **Pigeon app on-device**: pigeon.newyorkai.org — transcribes on phone, uploads `.md` alongside audio

If rclone not configured:
```bash
powershell.exe -ExecutionPolicy Bypass -File ops/scripts/setup-pigeon.ps1
```

After the script runs, tell user how many new entries were added and remind them: "Run /voice to route these notes to the right places."

### Scheduled Pigeon Transcription (every 10 minutes)

Check if already set up or declined:

**macOS/Linux:**
```bash
if launchctl list 2>/dev/null | grep -q "com.pigeon.transcribe"; then
    echo "SCHEDULED"
elif [ -f .voice/no-pigeon-schedule ]; then
    echo "DECLINED"
else
    echo "NOT_SCHEDULED"
fi
```

**Windows:**
```bash
powershell.exe -Command "if (Get-ScheduledTask -TaskName 'PigeonTranscribe' -ErrorAction SilentlyContinue) { 'SCHEDULED' } elseif (Test-Path '.voice/no-pigeon-schedule') { 'DECLINED' } else { 'NOT_SCHEDULED' }"
```

**If "SCHEDULED" or "DECLINED"**, skip to Auto-Routing.

**If "NOT_SCHEDULED"**, ask the user:

"Want to set up automatic transcription from Google Drive? It will check for new recordings every 10 minutes (7am–midnight)."

Options: "Yes, set it up" / "No, I'll run manually"

**If they say yes:**

**macOS/Linux** — create the launchd plist:

```bash
VAULT_PATH="$(pwd)"
cat > ~/Library/LaunchAgents/com.pigeon.transcribe.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.pigeon.transcribe</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${VAULT_PATH}/ops/scripts/scheduled/pigeon-transcribe.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartCalendarInterval</key>
    <array>
        <dict><key>Minute</key><integer>0</integer></dict>
        <dict><key>Minute</key><integer>10</integer></dict>
        <dict><key>Minute</key><integer>20</integer></dict>
        <dict><key>Minute</key><integer>30</integer></dict>
        <dict><key>Minute</key><integer>40</integer></dict>
        <dict><key>Minute</key><integer>50</integer></dict>
    </array>
    <key>StandardOutPath</key>
    <string>/tmp/pigeon-transcribe.out</string>
    <key>StandardErrorPath</key>
    <string>/tmp/pigeon-transcribe.err</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>HOME</key>
        <string>${HOME}</string>
    </dict>
</dict>
</plist>
EOF
```

Make the script executable and load:
```bash
chmod +x "$VAULT_PATH/ops/scripts/scheduled/pigeon-transcribe.sh"
launchctl load ~/Library/LaunchAgents/com.pigeon.transcribe.plist
```

Tell user: "Pigeon transcription is set up. It checks Google Drive every 10 minutes (7am–midnight). Check logs at `/tmp/pigeon-transcribe.out`."

**Windows** — create a scheduled task:

```bash
powershell.exe -ExecutionPolicy Bypass -Command "
\$scriptPath = Join-Path (Get-Location) 'ops/scripts/scheduled/pigeon-transcribe.ps1'
\$existing = Get-ScheduledTask -TaskName 'PigeonTranscribe' -ErrorAction SilentlyContinue
if (\$existing) { Unregister-ScheduledTask -TaskName 'PigeonTranscribe' -Confirm:\$false }
\$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument \`\"-ExecutionPolicy Bypass -NoProfile -File \`\"\$scriptPath\`\"\`\"
\$trigger = New-ScheduledTaskTrigger -Once -At '07:00AM' -RepetitionInterval (New-TimeSpan -Minutes 10) -RepetitionDuration (New-TimeSpan -Hours 17)
\$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Register-ScheduledTask -TaskName 'PigeonTranscribe' -Action \$action -Trigger \$trigger -Settings \$settings -Description 'Pigeon transcription (checks Drive every 10min, 7am-midnight)'
"
```

Tell user: "Pigeon transcription is set up. It checks Google Drive every 10 minutes (7am–midnight). Check Task Scheduler for 'PigeonTranscribe'."

**If they say no**:
```bash
touch .voice/no-pigeon-schedule
```

---

## Source: Local Folder

For users who sync recordings to a local folder (iCloud Drive, Dropbox, Obsidian Sync, etc.).

### Setup Checks

#### 1. Verify folder exists and has recordings

```bash
LOCAL_PATH=$(cat .voice/local-path 2>/dev/null)
if [ -z "$LOCAL_PATH" ] || [ ! -d "$LOCAL_PATH" ]; then
    echo "FOLDER_MISSING"
else
    find "$LOCAL_PATH" -maxdepth 2 -name "*.m4a" -type f 2>/dev/null | wc -l
fi
```

**If "FOLDER_MISSING"**, tell user the path doesn't exist and ask them to check it.

#### 2. Check `hear` tool (same as Voice Memos section)

```bash
which hear &>/dev/null && echo "READY"
```

If not ready, install it (same steps as Voice Memos section above).

### Processing Flow (Local Folder)

#### 1. Detect first run vs. ongoing

```bash
if [ -s .voice/local-processed ]; then echo "ONGOING"; else echo "FIRST_RUN"; fi
```

#### 2. First Run Flow

Show count, ask how far back, mark older files as processed.

```bash
LOCAL_PATH=$(cat .voice/local-path)
find "$LOCAL_PATH" -maxdepth 2 -name "*.m4a" -type f | wc -l
```

Use AskUserQuestion with options: "Last 5 memos" / "Last week" / "Last month" / "All of them"

#### 3. Ongoing Run Flow

Find recordings not yet processed:
```bash
LOCAL_PATH=$(cat .voice/local-path)
find "$LOCAL_PATH" -maxdepth 2 -name "*.m4a" -type f | while read filepath; do
    filename=$(basename "$filepath")
    grep -qxF "$filename" .voice/local-processed || echo "$filepath"
done
```

#### 4. Transcribe and append

For each new recording, check for companion `.md` file first (same name, `.md` extension). If found, use it. Otherwise transcribe with `hear`:

```bash
~/.local/bin/hear -d -i "$filepath"
```

Append to voice.md:
```markdown
## Memo - [date from filename or file modification time]

[transcription text]

```

#### 5. Mark as processed

```bash
echo "$filename" >> .voice/local-processed
```

#### 6. Summary

Tell user how many memos transcribed and remind: "Run /voice to route these notes to the right places."

### Reset

To re-process all local folder recordings:
```bash
rm .voice/local-processed
```

To change local folder path:
```bash
rm .voice/local-path .voice/source
```

---

## Auto-Routing (voice-auto)

After transcription is set up (any source), offer to schedule automatic routing — this runs `/voice` to sort transcribed notes into the right files.

Check if already set up or declined:

**macOS/Linux:**
```bash
if launchctl list 2>/dev/null | grep -q "com.claude.voice-auto"; then
    echo "SCHEDULED"
elif [ -f .voice/no-auto-route ]; then
    echo "DECLINED"
else
    echo "NOT_SCHEDULED"
fi
```

**Windows:**
```bash
powershell.exe -Command "if (Get-ScheduledTask -TaskName 'VoiceAutoRoute' -ErrorAction SilentlyContinue) { 'SCHEDULED' } elseif (Test-Path '.voice/no-auto-route') { 'DECLINED' } else { 'NOT_SCHEDULED' }"
```

**If "SCHEDULED" or "DECLINED"**, skip this section.

**If "NOT_SCHEDULED"**, ask the user:

"Want Claude to automatically route your voice notes? Every hour (30 minutes after transcription), Claude reads voice.md and sorts notes into tasks.md, delegation.md, and project files."

Options: "Yes, set it up" / "No, I'll run /voice manually"

**If they say yes:**

**macOS/Linux** — create the launchd plist:

```bash
VAULT_PATH="$(pwd)"
cat > ~/Library/LaunchAgents/com.claude.voice-auto.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.claude.voice-auto</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${VAULT_PATH}/ops/scripts/scheduled/voice-auto.sh</string>
    </array>
    <key>StartCalendarInterval</key>
    <array>
        <dict><key>Hour</key><integer>8</integer><key>Minute</key><integer>30</integer></dict>
        <dict><key>Hour</key><integer>9</integer><key>Minute</key><integer>30</integer></dict>
        <dict><key>Hour</key><integer>10</integer><key>Minute</key><integer>30</integer></dict>
        <dict><key>Hour</key><integer>11</integer><key>Minute</key><integer>30</integer></dict>
        <dict><key>Hour</key><integer>12</integer><key>Minute</key><integer>30</integer></dict>
        <dict><key>Hour</key><integer>13</integer><key>Minute</key><integer>30</integer></dict>
        <dict><key>Hour</key><integer>14</integer><key>Minute</key><integer>30</integer></dict>
        <dict><key>Hour</key><integer>15</integer><key>Minute</key><integer>30</integer></dict>
        <dict><key>Hour</key><integer>16</integer><key>Minute</key><integer>30</integer></dict>
        <dict><key>Hour</key><integer>17</integer><key>Minute</key><integer>30</integer></dict>
        <dict><key>Hour</key><integer>18</integer><key>Minute</key><integer>30</integer></dict>
        <dict><key>Hour</key><integer>19</integer><key>Minute</key><integer>30</integer></dict>
        <dict><key>Hour</key><integer>20</integer><key>Minute</key><integer>30</integer></dict>
        <dict><key>Hour</key><integer>21</integer><key>Minute</key><integer>30</integer></dict>
        <dict><key>Hour</key><integer>22</integer><key>Minute</key><integer>30</integer></dict>
        <dict><key>Hour</key><integer>23</integer><key>Minute</key><integer>30</integer></dict>
        <dict><key>Hour</key><integer>0</integer><key>Minute</key><integer>30</integer></dict>
    </array>
    <key>StandardOutPath</key>
    <string>/tmp/voice-auto.out</string>
    <key>StandardErrorPath</key>
    <string>/tmp/voice-auto.err</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>HOME</key>
        <string>${HOME}</string>
    </dict>
</dict>
</plist>
EOF
```

Make the script executable and load:
```bash
chmod +x "$VAULT_PATH/ops/scripts/scheduled/voice-auto.sh"
launchctl load ~/Library/LaunchAgents/com.claude.voice-auto.plist
```

Tell user: "Auto-routing is set up. Claude will run `/voice` every hour at :30 (30 minutes after transcription). Check logs at `/tmp/voice-auto.out`."

**Windows** — create a scheduled task:

```bash
powershell.exe -ExecutionPolicy Bypass -Command "
$scriptPath = Join-Path (Get-Location) 'ops/scripts/scheduled/voice-auto.ps1'
$existing = Get-ScheduledTask -TaskName 'VoiceAutoRoute' -ErrorAction SilentlyContinue
if ($existing) { Unregister-ScheduledTask -TaskName 'VoiceAutoRoute' -Confirm:`$false }
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument \"-ExecutionPolicy Bypass -NoProfile -File `\"$scriptPath`\"\"
$trigger = New-ScheduledTaskTrigger -Once -At '08:30AM' -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Hours 16)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Register-ScheduledTask -TaskName 'VoiceAutoRoute' -Action $action -Trigger $trigger -Settings $settings -Description 'Claude voice auto-routing (runs hourly at :30)'
"
```

Tell user: "Auto-routing is set up. Claude will run `/voice` every hour at :30 (30 minutes after transcription). Check Task Scheduler for 'VoiceAutoRoute'."

**If they say no**:
```bash
touch .voice/no-auto-route
```

---

## Managing Scheduled Jobs

### macOS/Linux

To check status:
```bash
launchctl list | grep -E "voicememos|voice-auto|pigeon"
```

To view logs:
```bash
cat /tmp/voicememos-transcribe.out
cat /tmp/voice-auto.out
```

To disable transcription:
```bash
launchctl unload ~/Library/LaunchAgents/com.voicememos.transcribe.plist
```

To disable auto-routing:
```bash
launchctl unload ~/Library/LaunchAgents/com.claude.voice-auto.plist
```

To re-enable:
```bash
launchctl load ~/Library/LaunchAgents/com.voicememos.transcribe.plist
launchctl load ~/Library/LaunchAgents/com.claude.voice-auto.plist
```

### Windows

To check status:
```bash
powershell.exe -Command "Get-ScheduledTask -TaskName 'PigeonTranscribe','VoiceAutoRoute' -ErrorAction SilentlyContinue | Format-Table TaskName,State"
```

To disable transcription:
```bash
powershell.exe -Command "Unregister-ScheduledTask -TaskName 'PigeonTranscribe' -Confirm:`$false"
```

To disable auto-routing:
```bash
powershell.exe -Command "Unregister-ScheduledTask -TaskName 'VoiceAutoRoute' -Confirm:`$false"
```

To re-enable, run `/setup-transcription` again.

## Edge Cases

- **Transcription fails on a file**: Note which file, continue with others, report at end
- **Empty transcription**: Some memos may be too short or unclear - note this, still mark as processed

## Reset

To re-process all voice memos:
```bash
rm .voice/memos-processed
```

To re-process all pigeon recordings:
```bash
rm .voice/pigeon-processed .voice/pigeon-downloaded
```

To change source:
```bash
rm .voice/source
```
