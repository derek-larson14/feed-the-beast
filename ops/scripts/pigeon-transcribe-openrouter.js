/**
 * Pigeon Transcription — Google Apps Script (OpenRouter variant)
 *
 * This is the OpenRouter version of the transcription script.
 * The primary/simpler version uses the Gemini API directly:
 *   pigeon-transcribe.js
 *
 * Use this variant if you want to avoid Google Cloud Billing
 * or want cheaper transcription via Gemini Flash Lite on OpenRouter.
 *
 * Watches a Google Drive folder for new .m4a recordings,
 * transcribes them via OpenRouter (OpenAI-compatible API),
 * and saves each transcript as a companion .md file.
 *
 * Setup:
 * 1. Go to script.google.com -> New Project
 * 2. Paste this entire file
 * 3. Replace OPENROUTER_API_KEY with your key from openrouter.ai
 * 4. Update appsscript.json (Project Settings -> check "Show appsscript.json"):
 *    {
 *      "timeZone": "America/New_York",
 *      "dependencies": {},
 *      "exceptionLogging": "STACKDRIVER",
 *      "runtimeVersion": "V8",
 *      "oauthScopes": [
 *        "https://www.googleapis.com/auth/drive.readonly",
 *        "https://www.googleapis.com/auth/drive.file",
 *        "https://www.googleapis.com/auth/script.external_request",
 *        "https://www.googleapis.com/auth/script.scriptapp"
 *      ]
 *    }
 * 5. Select "setup" from the function dropdown, click Run
 * 6. Approve permissions when prompted
 * 7. Done — checks for new recordings every 5 minutes
 */

const CONFIG = {
  // Get your API key at https://openrouter.ai/keys
  OPENROUTER_API_KEY: 'YOUR_API_KEY_HERE',

  // Folder name on Google Drive where Pigeon saves recordings
  DRIVE_FOLDER: 'pigeon',

  // OpenRouter model — gemini-2.0-flash-lite is cheapest ($0.075/M audio tokens)
  MODEL: 'google/gemini-2.0-flash-lite',
};

const DRIVE_API = 'https://www.googleapis.com/drive/v3';

// --- Setup & Triggers ---

/**
 * Run this once to set up the automatic trigger.
 */
function setup() {
  ScriptApp.getProjectTriggers().forEach(t => ScriptApp.deleteTrigger(t));

  ScriptApp.newTrigger('processNewRecordings')
    .timeBased()
    .everyMinutes(5)
    .create();

  const props = PropertiesService.getScriptProperties();
  if (!props.getProperty('processedFiles')) {
    props.setProperty('processedFiles', JSON.stringify([]));
  }

  Logger.log('Setup complete. Trigger will check for new recordings every 5 minutes.');
  processNewRecordings();
}

/**
 * Run this to clear the processed list and re-process all files.
 */
function reset() {
  PropertiesService.getScriptProperties().setProperty('processedFiles', JSON.stringify([]));
  Logger.log('Processed list cleared. Next run will re-process all files.');
}

// --- Main ---

/**
 * Main function — called by the trigger every 5 minutes.
 */
function processNewRecordings() {
  const token = ScriptApp.getOAuthToken();

  const folderId = findFolderId_(token, CONFIG.DRIVE_FOLDER);
  if (!folderId) {
    Logger.log('Folder "' + CONFIG.DRIVE_FOLDER + '" not found on Drive');
    return;
  }

  const props = PropertiesService.getScriptProperties();
  const processed = JSON.parse(props.getProperty('processedFiles') || '[]');
  const files = listM4aFiles_(token, folderId);
  let newCount = 0;

  for (const file of files) {
    if (processed.includes(file.id)) continue;

    Logger.log('Transcribing: ' + file.name);

    try {
      const blob = downloadFile_(token, file.id);
      const transcript = transcribeWithOpenRouter_(blob, file.mimeType);
      if (transcript) {
        saveTranscript_(token, folderId, file.name, transcript);
        processed.push(file.id);
        newCount++;
      }
    } catch (e) {
      Logger.log('Error transcribing ' + file.name + ': ' + e.message);
    }
  }

  props.setProperty('processedFiles', JSON.stringify(processed));

  if (newCount > 0) {
    Logger.log('Transcribed ' + newCount + ' new recording(s)');
  }
}

// --- Drive REST API (no DriveApp = no full drive scope) ---

function findFolderId_(token, name) {
  const query = "name='" + name + "' and mimeType='application/vnd.google-apps.folder' and trashed=false";
  const url = DRIVE_API + '/files?q=' + encodeURIComponent(query) + '&fields=files(id)';

  const resp = UrlFetchApp.fetch(url, {
    headers: { Authorization: 'Bearer ' + token },
    muteHttpExceptions: true
  });

  const result = JSON.parse(resp.getContentText());
  return result.files && result.files.length > 0 ? result.files[0].id : null;
}

function listM4aFiles_(token, folderId) {
  const query = "'" + folderId + "' in parents and trashed=false";
  const url = DRIVE_API + '/files?q=' + encodeURIComponent(query)
    + '&fields=files(id,name,mimeType)'
    + '&orderBy=createdTime';

  const resp = UrlFetchApp.fetch(url, {
    headers: { Authorization: 'Bearer ' + token },
    muteHttpExceptions: true
  });

  const result = JSON.parse(resp.getContentText());
  return (result.files || []).filter(f => f.name.endsWith('.m4a'));
}

function downloadFile_(token, fileId) {
  const url = DRIVE_API + '/files/' + fileId + '?alt=media';

  return UrlFetchApp.fetch(url, {
    headers: { Authorization: 'Bearer ' + token },
    muteHttpExceptions: true
  }).getBlob();
}

function findFileId_(token, folderId, name) {
  const query = "name='" + name + "' and '" + folderId + "' in parents and trashed=false";
  const url = DRIVE_API + '/files?q=' + encodeURIComponent(query) + '&fields=files(id)';

  const resp = UrlFetchApp.fetch(url, {
    headers: { Authorization: 'Bearer ' + token },
    muteHttpExceptions: true
  });

  const result = JSON.parse(resp.getContentText());
  return result.files && result.files.length > 0 ? result.files[0].id : null;
}

function createFile_(token, folderId, name, content) {
  const metadata = JSON.stringify({ name: name, parents: [folderId], mimeType: 'text/plain' });
  const boundary = 'pigeon_boundary';
  const body = '--' + boundary + '\r\n'
    + 'Content-Type: application/json; charset=UTF-8\r\n\r\n'
    + metadata + '\r\n'
    + '--' + boundary + '\r\n'
    + 'Content-Type: text/plain; charset=UTF-8\r\n\r\n'
    + content + '\r\n'
    + '--' + boundary + '--';

  UrlFetchApp.fetch('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart', {
    method: 'post',
    headers: { Authorization: 'Bearer ' + token },
    contentType: 'multipart/related; boundary=' + boundary,
    payload: body,
    muteHttpExceptions: true
  });
}

function updateFile_(token, fileId, content) {
  UrlFetchApp.fetch('https://www.googleapis.com/upload/drive/v3/files/' + fileId + '?uploadType=media', {
    method: 'patch',
    headers: { Authorization: 'Bearer ' + token },
    contentType: 'text/plain',
    payload: content,
    muteHttpExceptions: true
  });
}

// --- OpenRouter Transcription ---

function transcribeWithOpenRouter_(blob, mimeType) {
  const base64 = Utilities.base64Encode(blob.getBytes());

  const url = 'https://openrouter.ai/api/v1/chat/completions';

  const payload = {
    model: CONFIG.MODEL,
    messages: [{
      role: 'user',
      content: [
        {
          type: 'text',
          text: 'Transcribe this audio recording. Return only the transcript text, nothing else. No labels, no timestamps, no formatting — just the words spoken.'
        },
        {
          type: 'input_audio',
          input_audio: {
            data: base64,
            format: 'mp4'
          }
        }
      ]
    }]
  };

  const response = UrlFetchApp.fetch(url, {
    method: 'post',
    contentType: 'application/json',
    headers: {
      'Authorization': 'Bearer ' + CONFIG.OPENROUTER_API_KEY,
      'HTTP-Referer': 'https://script.google.com',
      'X-Title': 'Pigeon Transcription'
    },
    payload: JSON.stringify(payload),
    muteHttpExceptions: true
  });

  const result = JSON.parse(response.getContentText());

  if (result.error) {
    throw new Error(result.error.message);
  }

  const text = result.choices?.[0]?.message?.content;
  return text ? text.trim() : null;
}

// --- Transcript Output ---

/**
 * Save transcript as a companion .md file (same name as audio, .md extension).
 * Matches the format used by Pigeon's on-device transcription,
 * so the Mac-side script handles both sources the same way.
 */
function saveTranscript_(token, folderId, filename, transcript) {
  const mdFilename = filename.replace(/\.m4a$/, '.md');

  const existingId = findFileId_(token, folderId, mdFilename);

  if (existingId) {
    updateFile_(token, existingId, transcript);
  } else {
    createFile_(token, folderId, mdFilename, transcript);
  }
}
