#Requires -Version 5.1
# Pigeon Transcription (Windows)
# Pulls recordings from Google Drive, appends transcripts to voice.md
# Uses companion .md transcript files (from Apps Script or Pigeon on-device transcription)
# No local transcription fallback on Windows — files without companion .md are skipped
# Runs on a schedule via Task Scheduler — set up by setup-pigeon.ps1
# Config at $env:USERPROFILE\.pigeon\config (workspace path)

# Time guard: only run 7am–midnight (skip overnight if scheduled 24/7)
$hour = (Get-Date).Hour
if ($hour -lt 7) { exit 0 }

$ErrorActionPreference = "Stop"

$ConfigFile = Join-Path $env:USERPROFILE ".pigeon\config"
$PigeonDir = Join-Path $env:USERPROFILE "Sync\pigeon"
$DriveAudio = "gdrive:pigeon/audio"
$DriveTranscripts = "gdrive:pigeon/transcripts"

# Load workspace path from config
if (-not (Test-Path $ConfigFile)) {
    Write-Host "Error: no config at $ConfigFile"
    Write-Host "Run setup-pigeon.ps1 first"
    exit 1
}

# Parse key=value config file
$config = @{}
Get-Content $ConfigFile | ForEach-Object {
    if ($_ -match '^\s*([^#=]+?)\s*=\s*(.+?)\s*$') {
        $config[$Matches[1]] = $Matches[2]
    }
}

$Workspace = $config["WORKSPACE"]
if ([string]::IsNullOrWhiteSpace($Workspace) -or -not (Test-Path $Workspace)) {
    Write-Host "Error: workspace not found at $Workspace"
    exit 1
}

$VoiceDir = Join-Path $Workspace ".voice"
$DownloadedFile = Join-Path $VoiceDir "pigeon-downloaded"
$ProcessedFile = Join-Path $VoiceDir "pigeon-processed"
$VoiceMd = Join-Path $Workspace "voice.md"

New-Item -ItemType Directory -Path $VoiceDir -Force | Out-Null

# Find rclone
$RclonePath = (Get-Command rclone -ErrorAction SilentlyContinue).Source
if (-not $RclonePath) {
    # Check common Windows install locations
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Programs\rclone\rclone.exe"),
        (Join-Path $env:ProgramFiles "rclone\rclone.exe")
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { $RclonePath = $c; break }
    }
}

New-Item -ItemType Directory -Path $PigeonDir -Force | Out-Null
if (-not (Test-Path $DownloadedFile)) { New-Item -ItemType File -Path $DownloadedFile -Force | Out-Null }
if (-not (Test-Path $ProcessedFile)) { New-Item -ItemType File -Path $ProcessedFile -Force | Out-Null }

# Step 1: Pull new files from Google Drive
if ($RclonePath) {
    $remotes = & $RclonePath listremotes 2>$null
    if ($remotes -match "^gdrive:") {
        Write-Host "Checking Google Drive for new recordings..."
        $files = & $RclonePath lsf $DriveAudio --include "*.m4a" 2>$null
        $downloaded = @(Get-Content $DownloadedFile -ErrorAction SilentlyContinue)

        foreach ($filename in $files) {
            $filename = $filename.Trim()
            if ([string]::IsNullOrWhiteSpace($filename)) { continue }

            if ($downloaded -contains $filename) { continue }

            Write-Host "Downloading: $filename"
            & $RclonePath copy "$DriveAudio/$filename" $PigeonDir

            # Pull companion transcript if it exists
            $mdFile = $filename -replace '\.m4a$', '.md'
            & $RclonePath copy "$DriveTranscripts/$mdFile" $PigeonDir 2>$null

            # Append to downloaded list (use explicit LF)
            [System.IO.File]::AppendAllText($DownloadedFile, "$filename`n")
        }
    } else {
        Write-Host "rclone not configured - skipping Drive pull"
    }
} else {
    Write-Host "rclone not found - skipping Drive pull"
}

# Step 2: Process new audio files
$newCount = 0
$processed = @(Get-Content $ProcessedFile -ErrorAction SilentlyContinue)

$m4aFiles = Get-ChildItem -Path $PigeonDir -Filter "*.m4a" -ErrorAction SilentlyContinue

foreach ($memo in $m4aFiles) {
    $filename = $memo.Name

    if ($processed -contains $filename) { continue }

    # Check for companion transcript
    $mdPath = Join-Path $PigeonDir ($filename -replace '\.m4a$', '.md')

    if (Test-Path $mdPath) {
        Write-Host "Using transcript: $filename"
        $transcript = Get-Content $mdPath -Raw
    } else {
        Write-Host "Skipping $filename - no transcript found. Set up Apps Script transcription (see /setup-transcription)."
        continue
    }

    # Parse date from filename: pigeon_YYYYMMDD_HHMMSS.m4a
    $dateMatch = [regex]::Match($filename, '(\d{8})_(\d{6})')
    if ($dateMatch.Success) {
        $d = $dateMatch.Groups[1].Value
        $t = $dateMatch.Groups[2].Value
        $created = "$($d.Substring(0,4))-$($d.Substring(4,2))-$($d.Substring(6,2)) $($t.Substring(0,2)):$($t.Substring(2,2))"
    } else {
        $created = $memo.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
    }

    # Append to voice.md (use explicit LF line endings)
    $entry = "`n## Pigeon - $created`n`n$transcript`n"
    [System.IO.File]::AppendAllText($VoiceMd, $entry)

    # Mark as processed
    [System.IO.File]::AppendAllText($ProcessedFile, "$filename`n")
    $newCount++
}

if ($newCount -gt 0) {
    Write-Host "Processed $newCount new memo(s)"
} else {
    Write-Host "No new memos to process"
}
