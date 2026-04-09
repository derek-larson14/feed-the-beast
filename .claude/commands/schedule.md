---
description: Set up a scheduled Claude session (launchd on Mac, Task Scheduler on Windows)
model: sonnet
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, AskUserQuestion
---

# Schedule a Claude Command

Set up a command to run automatically on a schedule. Creates a runner script and a system-level scheduled job.

## Step 0: Detect OS

```bash
uname -s 2>/dev/null || echo "Windows"
```

If the output contains "MINGW", "CYGWIN", "MSYS", or "Windows", this is **Windows**. Use PowerShell and Task Scheduler. Otherwise, use bash and launchd.

## Step 1: What to Schedule

Use AskUserQuestion:

"What do you want to run on a schedule?"

Offer common options plus a custom option:
- "/morning — morning brief"
- "/delegate — process delegation queue"
- "/voice-router — route voice notes"
- "Custom command"

If they pick custom, ask what command or prompt to run.

## Step 2: When to Run

Use AskUserQuestion:

"How often should it run?"

Options:
- "Daily (pick a time)"
- "Multiple times a day (pick times)"
- "Weekly (pick a day and time)"
- "Every N hours"

Then ask for the specific time(s). Default suggestions:
- Morning brief: daily at 8:30am
- Delegate: daily at 9am
- Voice router: every 2 hours, 8am-10pm

## Step 3: Check for Conflicts

```bash
# macOS
ls ~/Library/LaunchAgents/com.claude.* 2>/dev/null | xargs -I {} basename {} .plist | sed 's/com.claude.//'
```

```bash
# Windows
powershell.exe -Command "Get-ScheduledTask | Where-Object {$_.TaskName -like 'Claude*'} | Format-Table TaskName,State" 2>/dev/null
```

If the same command is already scheduled, tell the user and ask if they want to replace it.

## Step 4: Create the Runner Script

Find the claude path:
```bash
which claude
```

### macOS/Linux

Create `ops/scripts/scheduled/TASKNAME.sh`:

```bash
#!/bin/bash
umask 077
cd VAULT_PATH

CLAUDE_PATH/claude -p "COMMAND" \
  --max-turns 25 \
  --dangerously-skip-permissions \
  >ops/logs/TASKNAME.out 2>ops/logs/TASKNAME.err &
CLAUDE_PID=$!

# Kill after 10 minutes to prevent hung processes blocking the next run
( sleep 600; kill $CLAUDE_PID 2>/dev/null ) &
TIMER_PID=$!

wait $CLAUDE_PID
EXIT_CODE=$?
kill $TIMER_PID 2>/dev/null

if [ $EXIT_CODE -eq 137 ] || [ $EXIT_CODE -eq 143 ]; then
    echo "$(date): TIMEOUT — Claude process killed after 10min" >> ops/logs/TASKNAME.err
    exit 1
fi
exit $EXIT_CODE
```

Replace VAULT_PATH with `$(pwd)`, CLAUDE_PATH with the result of `which claude`, COMMAND with the user's command, and TASKNAME with the task identifier.

Make sure the logs directory exists:
```bash
mkdir -p ops/logs
```

Make it executable:
```bash
chmod +x ops/scripts/scheduled/TASKNAME.sh
```

### Windows

Create `ops/scripts/scheduled/TASKNAME.ps1`:

```powershell
Set-Location "VAULT_PATH"

$proc = Start-Process -FilePath "claude" -ArgumentList '-p', '"COMMAND"', '--max-turns', '25', '--dangerously-skip-permissions' -NoNewWindow -PassThru -RedirectStandardOutput "ops/logs/TASKNAME.out" -RedirectStandardError "ops/logs/TASKNAME.err"

# Kill after 10 minutes
$timer = Start-Sleep -Seconds 600
if (!$proc.HasExited) {
    $proc.Kill()
    Add-Content "ops/logs/TASKNAME.err" "$(Get-Date): TIMEOUT — Claude process killed after 10min"
    exit 1
}
exit $proc.ExitCode
```

## Step 5: Create the Scheduled Job

### macOS — launchd plist

Write to `~/Library/LaunchAgents/com.claude.TASKNAME.plist`.

Use `StartCalendarInterval` (not `StartInterval`). StartInterval gets confused by macOS sleep/wake cycles. StartCalendarInterval checks the wall clock and catches up on missed runs.

**Daily at a specific time (e.g., 9am):**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.claude.TASKNAME</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>VAULT_PATH/ops/scripts/scheduled/TASKNAME.sh</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>9</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>/tmp/claude.TASKNAME.out</string>
    <key>StandardErrorPath</key>
    <string>/tmp/claude.TASKNAME.err</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>HOME</key>
        <string>HOME_PATH</string>
    </dict>
</dict>
</plist>
```

**Multiple times a day:** Use an array of dicts under `StartCalendarInterval`, one per time.

**Weekly (e.g., Mondays at 10am):** Add `<key>Weekday</key><integer>1</integer>` inside the dict. Weekday 0 = Sunday, 1 = Monday, etc.

**Every N hours:** Create one dict per hour you want it to fire (e.g., 8, 10, 12, 14, 16, 18, 20 for every 2 hours during waking hours).

Load the job:
```bash
launchctl load ~/Library/LaunchAgents/com.claude.TASKNAME.plist
```

### Windows — Task Scheduler

```bash
powershell.exe -ExecutionPolicy Bypass -Command "
$scriptPath = 'VAULT_PATH/ops/scripts/scheduled/TASKNAME.ps1'
$existing = Get-ScheduledTask -TaskName 'ClaudeTASKNAME' -ErrorAction SilentlyContinue
if ($existing) { Unregister-ScheduledTask -TaskName 'ClaudeTASKNAME' -Confirm:$false }
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument \"-ExecutionPolicy Bypass -NoProfile -File $scriptPath\"
$trigger = New-ScheduledTaskTrigger -Daily -At 'TIME'
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Register-ScheduledTask -TaskName 'ClaudeTASKNAME' -Action $action -Trigger $trigger -Settings $settings -Description 'DESCRIPTION'
"
```

For repeating triggers (every N hours), use `-RepetitionInterval` and `-RepetitionDuration`.

## Step 6: Verify

### macOS
```bash
launchctl list | grep com.claude.TASKNAME
```

### Windows
```bash
powershell.exe -Command "Get-ScheduledTask -TaskName 'ClaudeTASKNAME'"
```

Tell the user:
- What was scheduled and when
- Where to find output logs: `ops/logs/TASKNAME.out` (detailed) and `/tmp/claude.TASKNAME.out` (launchd wrapper)
- How to check status: `launchctl list | grep claude` (Mac) or Task Scheduler (Windows)
- How to disable: `launchctl unload ~/Library/LaunchAgents/com.claude.TASKNAME.plist` (Mac)

## Managing Scheduled Jobs

### List all scheduled Claude jobs

**macOS:**
```bash
launchctl list | grep com.claude
```

**Windows:**
```bash
powershell.exe -Command "Get-ScheduledTask | Where-Object {$_.TaskName -like 'Claude*'}"
```

### Remove a scheduled job

**macOS:**
```bash
launchctl unload ~/Library/LaunchAgents/com.claude.TASKNAME.plist
rm ~/Library/LaunchAgents/com.claude.TASKNAME.plist
rm ops/scripts/scheduled/TASKNAME.sh
```

**Windows:**
```bash
powershell.exe -Command "Unregister-ScheduledTask -TaskName 'ClaudeTASKNAME' -Confirm:$false"
rm ops/scripts/scheduled/TASKNAME.ps1
```

## Common Schedules Reference

| What | When | Why |
|------|------|-----|
| /morning | Daily 8:30am | Start the day with context |
| /delegate | Daily 9am | Process overnight task queue |
| /voice-router | Every 2h, 8am-10pm | Route voice notes as they come in |
| /weekly | Fridays 4pm | End-of-week review |
| /finance:check | Sundays 7pm | Weekly finance summary |

## Response Style

- Walk through each step, confirming choices before creating files
- After setup, show how to test it manually
- Keep it conversational, not technical
