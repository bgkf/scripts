#!/bin/bash
# =============================================================================
# Report on all agentic tools added to the following apps
# - CLAUDE DESKTOP/CODE
# - CHATGPT
# - CURSOR
# - GEMINI
# - RAYCAST
# =============================================================================

CURRENT_USER=$(stat -f "%Su" /dev/console 2>/dev/null)
[[ -z "$CURRENT_USER" || "$CURRENT_USER" == "root" ]] && CURRENT_USER=""

USER_HOME=""
if [[ -n "$CURRENT_USER" ]]; then
  USER_HOME=$(dscl . -read "/Users/${CURRENT_USER}" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
  [[ -z "$USER_HOME" ]] && USER_HOME="/Users/${CURRENT_USER}"
fi

HOSTNAME=$(hostname -s)
OS_VERSION=$(sw_vers -productVersion)
SERIAL=$(system_profiler SPHardwareDataType 2>/dev/null | awk '/Serial Number/ {print $NF}')
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# ── Helper: app version or "not_installed" ────────────────────────────────────
app_version() {
  [[ -d "$1" ]] || { echo "not_installed"; return; }
  /usr/bin/defaults read "${1}/Contents/Info" CFBundleShortVersionString 2>/dev/null \
    | tr -d '\n' || echo "unknown"
}

# ── Helper: read a JSON file, return [] on any error ─────────────────────────
safe_read() {
  [[ -f "$1" ]] && jq -c '.' "$1" 2>/dev/null || echo "[]"
}

# ═════════════════════════════════════════════════════════════════════════════
# CLAUDE DESKTOP
# Config: ~/Library/Application Support/Claude/claude_desktop_config.json
# Reads mcpServers keys → array of {name, type, command, enabled}
# ═════════════════════════════════════════════════════════════════════════════
CLAUDE_VERSION=$(app_version "/Applications/Claude.app")
CLAUDE_CONNECTIONS="[]"

if [[ "$CLAUDE_VERSION" != "not_installed" && -n "$USER_HOME" ]]; then
  for cfg in \
      "${USER_HOME}/Library/Application Support/Claude/claude_desktop_config.json" \
      "${USER_HOME}/.claude/claude_desktop_config.json"; do
    [[ -f "$cfg" ]] || continue
    CLAUDE_CONNECTIONS=$(jq -c '
      .mcpServers // {} | to_entries | map({
        name:    .key,
        type:    "mcp",
        command: (.value.command // ""),
        enabled: true
      })
    ' "$cfg" 2>/dev/null || echo "[]")
    break
  done
fi

# ═════════════════════════════════════════════════════════════════════════════
# CHATGPT
# Config: ~/Library/Application Support/OpenAI/ChatGPT/settings.json
# Reads enabledConnectors (array or object) → array of {name, type, enabled}
# ═════════════════════════════════════════════════════════════════════════════
CHATGPT_VERSION=$(app_version "/Applications/ChatGPT.app")
CHATGPT_CONNECTIONS="[]"

if [[ "$CHATGPT_VERSION" != "not_installed" && -n "$USER_HOME" ]]; then
  cfg="${USER_HOME}/Library/Application Support/OpenAI/ChatGPT/settings.json"
  if [[ -f "$cfg" ]]; then
    CHATGPT_CONNECTIONS=$(jq -c '
      (.enabledConnectors // .plugins // []) |
      if type == "array" then
        map({name: (. | tostring), type: "connector", enabled: true})
      elif type == "object" then
        to_entries | map({name: .key, type: "connector", enabled: (.value | if type == "boolean" then . else true end)})
      else [] end
    ' "$cfg" 2>/dev/null || echo "[]")
  fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# CURSOR
# Configs: ~/.cursor/mcp.json
#          ~/Library/Application Support/Cursor/User/settings.json
# ═════════════════════════════════════════════════════════════════════════════
CURSOR_VERSION=$(app_version "/Applications/Cursor.app")
CURSOR_CONNECTIONS="[]"

if [[ "$CURSOR_VERSION" != "not_installed" && -n "$USER_HOME" ]]; then
  CURSOR_SETTINGS="${USER_HOME}/Library/Application Support/Cursor/User/settings.json"
  CURSOR_MCP="${USER_HOME}/.cursor/mcp.json"

  # Build connections array by merging settings + mcp sources
  CURSOR_FROM_SETTINGS="[]"
  if [[ -f "$CURSOR_SETTINGS" ]]; then
    CURSOR_FROM_SETTINGS=$(jq -cn \
      --argjson cfg "$(jq '.' "$CURSOR_SETTINGS" 2>/dev/null || echo '{}')" '
      []
      + (if $cfg["remote.SSH.configFile"] then
           [{name: "SSH", type: "remote", enabled: true}]
         else [] end)
      + (if $cfg["github.copilot.enable"] == true then
           [{name: "GitHub Copilot", type: "ai", enabled: true}]
         else [] end)
      + (if ($cfg["cursor.aiModel"] // $cfg["cursor.general.aiModel"]) != null then
           [{name: ("AI Model: " + ($cfg["cursor.aiModel"] // $cfg["cursor.general.aiModel"])),
             type: "ai", enabled: true}]
         else [] end)
    ' 2>/dev/null || echo "[]")
  fi

  CURSOR_FROM_MCP="[]"
  if [[ -f "$CURSOR_MCP" ]]; then
    CURSOR_FROM_MCP=$(jq -c '
      .mcpServers // {} | to_entries | map({
        name:    .key,
        type:    "mcp",
        command: (.value.command // ""),
        enabled: true
      })
    ' "$CURSOR_MCP" 2>/dev/null || echo "[]")
  fi

  CURSOR_CONNECTIONS=$(jq -cn \
    --argjson a "$CURSOR_FROM_SETTINGS" \
    --argjson b "$CURSOR_FROM_MCP" \
    '$a + $b')
fi

# ═════════════════════════════════════════════════════════════════════════════
# GEMINI
# Detection: macOS Keychain entries for known com.google.* bundle IDs
# ═════════════════════════════════════════════════════════════════════════════
GEMINI_VERSION="not_installed"
for candidate in "/Applications/Gemini.app" "/Applications/Google AI.app"; do
  if [[ -d "$candidate" ]]; then
    GEMINI_VERSION=$(app_version "$candidate")
    break
  fi
done

GEMINI_CONNECTIONS="[]"
if [[ "$GEMINI_VERSION" != "not_installed" && -n "$CURRENT_USER" ]]; then
  declare -A GEMINI_MAP=(
    ["Google Drive"]="com.google.GoogleDrive"
    ["Gmail"]="com.google.Gmail"
    ["Calendar"]="com.google.Calendar"
    ["Google Docs"]="com.google.GoogleDocs"
    ["YouTube"]="com.google.YouTube"
    ["Maps"]="com.google.Maps"
  )

  GEMINI_ITEMS="[]"
  for svc in "Google Drive" "Gmail" "Calendar" "Google Docs" "YouTube" "Maps"; do
    if /usr/bin/security find-generic-password \
        -s "${GEMINI_MAP[$svc]}" -a "$CURRENT_USER" &>/dev/null; then
      GEMINI_ITEMS=$(jq -cn \
        --argjson arr "$GEMINI_ITEMS" \
        --arg name "$svc" \
        '$arr + [{name: $name, type: "google_workspace", enabled: true}]')
    fi
  done
  GEMINI_CONNECTIONS="$GEMINI_ITEMS"
fi

# ═════════════════════════════════════════════════════════════════════════════
# RAYCAST
# Detection: Keychain entries (Raycast - <Service>), extensions dir count,
#            aiProvider/aiModel defaults keys
# ═════════════════════════════════════════════════════════════════════════════
RAYCAST_VERSION=$(app_version "/Applications/Raycast.app")
RAYCAST_EXT_COUNT=0
RAYCAST_CONNECTIONS="[]"

if [[ "$RAYCAST_VERSION" != "not_installed" && -n "$USER_HOME" ]]; then
  EXTENSIONS_DIR="${USER_HOME}/Library/Application Support/com.raycast.macos/extensions"
  if [[ -d "$EXTENSIONS_DIR" ]]; then
    RAYCAST_EXT_COUNT=$(find "$EXTENSIONS_DIR" -maxdepth 1 -mindepth 1 -type d 2>/dev/null \
      | wc -l | tr -d ' ')
  fi

  RAYCAST_ITEMS="[]"
  for svc in "GitHub" "Slack" "Linear" "Jira" "Notion" "Google Calendar" "Spotify" "1Password"; do
    if /usr/bin/security find-generic-password \
        -s "Raycast - ${svc}" &>/dev/null; then
      RAYCAST_ITEMS=$(jq -cn \
        --argjson arr "$RAYCAST_ITEMS" \
        --arg name "$svc" \
        '$arr + [{name: $name, type: "extension", enabled: true}]')
    fi
  done

  AI_PROVIDER=$(/usr/bin/defaults read com.raycast.macos aiProvider 2>/dev/null || true)
  if [[ -n "$AI_PROVIDER" ]]; then
    AI_MODEL=$(/usr/bin/defaults read com.raycast.macos aiModel 2>/dev/null || true)
    AI_LABEL="${AI_PROVIDER}${AI_MODEL:+:${AI_MODEL}}"
    RAYCAST_ITEMS=$(jq -cn \
      --argjson arr "$RAYCAST_ITEMS" \
      --arg name "$AI_LABEL" \
      '$arr + [{name: $name, type: "ai_provider", enabled: true}]')
  fi

  RAYCAST_CONNECTIONS="$RAYCAST_ITEMS"
fi

# ═════════════════════════════════════════════════════════════════════════════
# EMIT FINAL JSON
# All values passed via --arg / --argjson — no bash interpolation in jq source
# ═════════════════════════════════════════════════════════════════════════════
RESULT=$(jq -cn \
  --arg      ts              "$TIMESTAMP" \
  --arg      hostname        "$HOSTNAME" \
  --arg      serial          "$SERIAL" \
  --arg      os_version      "$OS_VERSION" \
  --arg      current_user    "$CURRENT_USER" \
  --arg      claude_ver      "$CLAUDE_VERSION" \
  --argjson  claude_conns    "$CLAUDE_CONNECTIONS" \
  --arg      chatgpt_ver     "$CHATGPT_VERSION" \
  --argjson  chatgpt_conns   "$CHATGPT_CONNECTIONS" \
  --arg      cursor_ver      "$CURSOR_VERSION" \
  --argjson  cursor_conns    "$CURSOR_CONNECTIONS" \
  --arg      gemini_ver      "$GEMINI_VERSION" \
  --argjson  gemini_conns    "$GEMINI_CONNECTIONS" \
  --arg      raycast_ver     "$RAYCAST_VERSION" \
  --argjson  raycast_conns   "$RAYCAST_CONNECTIONS" \
  --argjson  raycast_exts    "$RAYCAST_EXT_COUNT" \
  '
  def tool($ver; $conns):
    { installed: ($ver != "not_installed"),
      version:   (if $ver == "not_installed" then null else $ver end),
      connections: $conns };

  {
    collected_at: $ts,
    device: {
      hostname:     $hostname,
      serial_number: (if $serial == "" then null else $serial end),
      os_version:   $os_version,
      current_user: (if $current_user == "" then null else $current_user end)
    },
    tools: {
      claude:  tool($claude_ver;  $claude_conns),
      chatgpt: tool($chatgpt_ver; $chatgpt_conns),
      cursor:  tool($cursor_ver;  $cursor_conns),
      gemini:  tool($gemini_ver;  $gemini_conns),
      raycast: (tool($raycast_ver; $raycast_conns) + {extensions_installed: $raycast_exts})
    }
  }
  ')

if [[ $? -ne 0 || -z "$RESULT" ]]; then
  echo "<r>error: json_serialization_failed</r>"
  exit 1
fi

echo "<r>${RESULT}</r>"
