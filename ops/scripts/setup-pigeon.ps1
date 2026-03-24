#Requires -Version 5.1
# Setup Pigeon Pipeline (Windows)
# Run from your workspace, or pass the workspace path as an argument.
#
# What it does:
# 1. Installs rclone (via winget or direct download)
# 2. Connects your Google Drive
# 3. Downloads the transcription script
# 4. Schedules transcription every hour via Task Scheduler
#
# After setup, recordings from Pigeon on your phone are
# automatically pulled and transcripts appended to voice.md.
#
# NOTE: Windows uses companion .md transcripts (from Apps Script or
# Pigeon on-device transcription). No local 'hear' tool needed.
# Set up Apps Script transcription at delegatewithclaude.com/voice

param(
    [string]$WorkspacePath
)

$ErrorActionPreference = "Stop"

$PigeonHome = Join-Path $env:USERPROFILE ".pigeon"
$PigeonDir = Join-Path $env:USERPROFILE "Sync\pigeon"
$TranscribeUrl = "https://raw.githubusercontent.com/derek-larson14/delegate/main/ops/scripts/scheduled/pigeon-transcribe.ps1"
$TaskName = "PigeonTranscribe"

Write-Host "=== Pigeon Pipeline Setup (Windows) ===" -ForegroundColor Cyan
Write-Host ""

# Detect workspace path
if ($WorkspacePath) {
    $Workspace = Resolve-Path $WorkspacePath | Select-Object -ExpandProperty Path
} elseif (Test-Path "CLAUDE.md") {
    $Workspace = $PWD.Path
} else {
    Write-Host "[!] Run this from your workspace folder (the one with CLAUDE.md)." -ForegroundColor Red
    Write-Host "    cd C:\path\to\claude-workspace" -ForegroundColor Red
    Write-Host "    .\ops\scripts\setup-pigeon.ps1" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path (Join-Path $Workspace "CLAUDE.md"))) {
    Write-Host "[!] No CLAUDE.md found in $Workspace" -ForegroundColor Red
    Write-Host "    Download the workspace first: delegatewithclaude.com/commands" -ForegroundColor Red
    exit 1
}

Write-Host "[ok] Workspace: $Workspace"

# Save config
New-Item -ItemType Directory -Path $PigeonHome -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $PigeonHome "config"), "WORKSPACE=$Workspace`n")

# Step 1: Find or install rclone
$RclonePath = (Get-Command rclone -ErrorAction SilentlyContinue).Source
if ($RclonePath) {
    Write-Host "[ok] rclone found at $RclonePath"
} else {
    # Check common Windows locations
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Programs\rclone\rclone.exe"),
        (Join-Path $env:ProgramFiles "rclone\rclone.exe")
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { $RclonePath = $c; break }
    }

    if ($RclonePath) {
        Write-Host "[ok] rclone found at $RclonePath"
    } else {
        Write-Host "[*] Installing rclone..."

        $rcloneDir = Join-Path $env:LOCALAPPDATA "Programs\rclone"
        New-Item -ItemType Directory -Path $rcloneDir -Force | Out-Null

        $tmpFile = Join-Path $env:TEMP "rclone-download.zip"
        try {
            Invoke-WebRequest -Uri "https://downloads.rclone.org/rclone-current-windows-amd64.zip" -OutFile $tmpFile -UseBasicParsing
            $tmpExtract = Join-Path $env:TEMP "rclone-extract"
            Expand-Archive -Path $tmpFile -DestinationPath $tmpExtract -Force

            # Find rclone.exe in extracted folder
            $rcloneExe = Get-ChildItem $tmpExtract -Recurse -Filter "rclone.exe" | Select-Object -First 1
            if ($rcloneExe) {
                Copy-Item $rcloneExe.FullName (Join-Path $rcloneDir "rclone.exe") -Force
                $RclonePath = Join-Path $rcloneDir "rclone.exe"

                # Add to user PATH
                $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
                if ($userPath -notlike "*$rcloneDir*") {
                    [Environment]::SetEnvironmentVariable("Path", "$userPath;$rcloneDir", "User")
                    $env:Path = "$env:Path;$rcloneDir"
                }
                Write-Host "[ok] rclone installed to $RclonePath"
            } else {
                Write-Host "[!] Could not find rclone.exe in download" -ForegroundColor Red
                exit 1
            }

            Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
            Remove-Item $tmpExtract -Recurse -Force -ErrorAction SilentlyContinue
        } catch {
            Write-Host "[!] Failed to download rclone: $_" -ForegroundColor Red
            Write-Host "    Install manually: https://rclone.org/install/" -ForegroundColor Red
            Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
            exit 1
        }
    }
}

# Step 2: Configure Google Drive remote
$remotes = & $RclonePath listremotes 2>$null
if ($remotes -match "^gdrive:") {
    Write-Host "[ok] gdrive remote already configured"
} else {
    Write-Host ""
    Write-Host "[*] Connecting Google Drive..."
    Write-Host "    A browser window will open. Sign in with your Google account."
    Write-Host ""
    & $RclonePath config create gdrive drive
    Write-Host ""
    Write-Host "[ok] Google Drive connected"
}

# Step 3: Test connection
Write-Host ""
Write-Host "[*] Testing Google Drive connection..."
$testResult = & $RclonePath lsd gdrive: 2>$null
if ($LASTEXITCODE -eq 0) {
    $testResult | Select-Object -First 3 | ForEach-Object { Write-Host $_ }
    Write-Host "[ok] Drive connection working"
} else {
    Write-Host "[!] Could not list Drive contents - check with: $RclonePath config" -ForegroundColor Yellow
}

$pigeonTest = & $RclonePath lsd gdrive:pigeon 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "[ok] pigeon/ folder found on Drive"
    $audioTest = & $RclonePath lsd gdrive:pigeon/audio 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[ok] pigeon/audio/ subfolder found"
    } else {
        Write-Host "[*] pigeon/audio/ subfolder not found - it appears after your first recording"
    }
    $transcriptsTest = & $RclonePath lsd gdrive:pigeon/transcripts 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[ok] pigeon/transcripts/ subfolder found"
    } else {
        Write-Host "[*] pigeon/transcripts/ subfolder not found - it appears after your first transcription"
    }
} else {
    Write-Host "[*] pigeon/ folder not on Drive yet - it appears after your first recording"
}

# Step 4: Create local directories
New-Item -ItemType Directory -Path $PigeonDir -Force | Out-Null
Write-Host "[ok] Local pigeon directory: $PigeonDir"

# Step 5: Note about transcription
Write-Host ""
Write-Host "[!] Windows uses companion .md transcripts (no local 'hear' tool)." -ForegroundColor Yellow
Write-Host "    Set up cloud transcription via one of these options:"
Write-Host "    - Apps Script (Gemini): delegatewithclaude.com/voice"
Write-Host "    - Pigeon app on-device transcription: pigeon.newyorkai.org"
Write-Host "    Both produce companion .md files that the pipeline picks up automatically."

# Step 6: Download transcription script
Write-Host ""
Write-Host "[*] Downloading transcription script..."
Invoke-WebRequest -Uri $TranscribeUrl -OutFile (Join-Path $PigeonHome "pigeon-transcribe.ps1") -UseBasicParsing
Write-Host "[ok] Saved to $PigeonHome\pigeon-transcribe.ps1"

# Step 7: Schedule via Task Scheduler
Write-Host ""
Write-Host "[*] Setting up scheduled task..."

# Remove existing task if present
$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existing) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

$scriptPath = Join-Path $PigeonHome "pigeon-transcribe.ps1"
$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-ExecutionPolicy Bypass -NoProfile -File `"$scriptPath`""

$trigger = New-ScheduledTaskTrigger `
    -Once `
    -At "08:00AM" `
    -RepetitionInterval (New-TimeSpan -Hours 1) `
    -RepetitionDuration (New-TimeSpan -Hours 16)

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Description "Pigeon voice memo transcription (runs hourly 8am-midnight)" | Out-Null

Write-Host "[ok] Scheduled transcription every hour (8am-midnight)"

Write-Host ""
Write-Host "=== Setup Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "How it works:"
Write-Host "  1. Record on your phone with Pigeon"
Write-Host "  2. Recordings upload to Google Drive"
Write-Host "  3. Apps Script transcribes them to companion .md files"
Write-Host "  4. Every hour, your PC pulls transcripts to $Workspace\voice.md"
Write-Host ""
Write-Host "Run /voice in Claude Code to route transcripts to tasks and notes."
