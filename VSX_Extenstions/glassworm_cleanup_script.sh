#!/bin/bash
# =============================================================================
# uninstall_extensions.sh
# Scans VS Code and Cursor extensions, compares against the Glassworm v2
# blocklist, and uninstalls any matches.
#
# Designed to run as root via Jamf Pro. All editor CLI calls are executed
# as the logged-in console user inside their launchd session so that the
# correct extension directory and user environment are used.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# JAMF / ROOT EXECUTION CONTEXT
#
# When Jamf runs this script as root:
#   • $HOME  resolves to /var/root — NOT the logged-in user's home directory
#   • Editor CLIs (code, cursor) must run as the console user so they resolve
#     ~/.vscode/extensions, ~/.cursor/extensions, and the user's display
#     session correctly.
#
# LOGGED_IN_USER  — human at the console  (via stat /dev/console)
# USER_HOME       — their home directory  (via dscl)
# USER_UID        — their numeric UID     (needed for launchctl asuser)
#
# All editor CLI invocations are wrapped with run_as_user(), which uses:
#   launchctl asuser <uid> sudo -u <user> HOME=<home> PATH=<path> <cli> …
#
# launchctl asuser puts the subprocess inside the user's launchd session,
# which is required for GUI-adjacent tools like the VS Code / Cursor CLIs.
# ---------------------------------------------------------------------------

# -- Resolve the console user ------------------------------------------------
LOGGED_IN_USER=$(stat -f '%Su' /dev/console 2>/dev/null || true)

# Fallback via scutil if stat didn't produce a usable result
if [[ -z "$LOGGED_IN_USER" || "$LOGGED_IN_USER" == "root" ]]; then
    LOGGED_IN_USER=$(scutil <<< "show State:/Users/ConsoleUser" \
        2>/dev/null | awk '/Name :/ && !/loginwindow/ { print $3; exit }' || true)
fi

if [[ -z "$LOGGED_IN_USER" || "$LOGGED_IN_USER" == "root" || "$LOGGED_IN_USER" == "loginwindow" ]]; then
    echo "[ERROR] Could not determine a logged-in console user. Aborting."
    exit 1
fi

USER_UID=$(id -u "$LOGGED_IN_USER")
USER_HOME=$(dscl . -read "/Users/$LOGGED_IN_USER" NFSHomeDirectory 2>/dev/null \
    | awk '{print $2}')

if [[ -z "$USER_HOME" || ! -d "$USER_HOME" ]]; then
    echo "[ERROR] Home directory for '${LOGGED_IN_USER}' not found (resolved: '${USER_HOME}')."
    exit 1
fi

# ---------------------------------------------------------------------------
# run_as_user <command> [args...]
#
# Executes a command as the console user inside their launchd session with
# HOME set to their actual home directory and a PATH that covers all common
# locations where the code / cursor CLI symlinks are installed.
# ---------------------------------------------------------------------------
EDITOR_PATH="/usr/local/bin:/opt/homebrew/bin:${USER_HOME}/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

run_as_user() {
    launchctl asuser "$USER_UID" \
        sudo -u "$LOGGED_IN_USER" \
             HOME="$USER_HOME" \
             PATH="$EDITOR_PATH" \
             "$@"
}

# ---------------------------------------------------------------------------
# LOGGING & EXTENSION ATTRIBUTE OUTPUT
#
# LOG_FILE  -- full run log written on every execution (overwrites).
#              Plain text, no ANSI codes, readable by any tool.
# EA_FILE   -- single-line result read by the companion EA script:
#              "0 matches" | "3 matches: ext.one, ext.two, ext.three"
#              Jamf inventory picks this up on the next recon.
# ---------------------------------------------------------------------------
LOG_FILE="/opt/glassworm-cleanup.log"
EA_FILE="/opt/glassworm-cleanup-ea.txt"

# Initialise log file (overwrite on each run)
: > "$LOG_FILE"

# Plain-text logger -- mirrors every message to LOG_FILE without colour codes
logf() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

# ---------------------------------------------------------------------------
# CONFIGURATION -- GlassWorm malicious Open VSX extension blocklist
# Source: glassworm-v2-packages.csv (socket.dev/supply-chain-attacks/glassworm-v2)
# Confirmed IOCs with verified publisher.name identifiers only.
# Last updated: 2026-03-16  |  Total: 128 extensions
# ---------------------------------------------------------------------------
BLOCKED_EXTENSIONS=(
    "aadarkcode.one-dark-material"
    "aligntool.extension-align-professional-tool"
    "anessaeah.php-intelephense-language-support"
    "angular-studio.ng-angular-extension"
    "awesome-codebase.codebase-dart-pro"
    "awesomeco.wonder-for-vscode-icons"
    "awwwadem.language-professional-tools"
    "baksmink.vscode-quokka-extension"
    "bhbpbarn.vsce-python-indent-extension"
    "blockstoks.easily-gitignore-manage"
    "brategmaqendaalar-studio.pro-prettyxml-formatter"
    "calow-dex.prisma-database-schema-tools"
    "catspace-studio.ng-angular-language"
    "cliagenball.cline-agent-extension"
    "clotomoto.code-way-editor"
    "cod-vok.arko-dev-devsecops"
    "codbro-dxp.explorer-xml-xquery"
    "codbroks.compile-runnner-extension"
    "codevunm-tm.cluster-kuberntes-manager"
    "codevunmis.csv-sql-tsv-rainbow"
    "codwayexten.code-way-extension"
    "coneditorfig.config-editor-extension"
    "cosmic-themes.sql-formatter"
    "craz2team.vscode-todo-extension"
    "crazy-ndkilddmn.vim-smart-tool"
    "croct-studio.antigravity-model-usage-dashboard"
    "crotoapp.vscode-xml-extension"
    "cud-dot-prod-studio.prettier-pro-vscode-extension"
    "cudra-production.vsce-prettier-pro"
    "daeumer-web.align-format-tool"
    "daeumer-web.es-linter-for-vs-code"
    "daeumer-web.style-align-extension"
    "dark-code-studio.flutter-extension"
    "densy-little-studio.wonder-for-vscode-icons"
    "dep-labs-studio.dep-proffesinal-extension"
    "dev-studio-sense.php-comp-tools-vscode"
    "dev-tm.code-python-indent-helper"
    "devmidu-studio.svg-better-extension"
    "dopbop-studio.vscode-tailwindcss-extension-toolkit"
    "errlenscre.error-lens-finder-ex"
    "exss-studio.yaml-professional-extension"
    "federicanc.dotenv-syntax-highlighting"
    "federicanc.envglow-syntax-highlighting"
    "flape-osx.align-code-format-tool"
    "floktokbok.autoimport-smart-tool"
    "flutxvs.vscode-kuberntes-extension"
    "gorth-tm.your-project-manager-organizer"
    "gvotcha.claude-code-extension"
    "gvotcha.claude-code-extensions"
    "icepower1997.glacier-cave-theme"
    "ilvvilab.php-composr-tool-extension"
    "inangalek.project-manager-extension"
    "intellipro.extension-json-intelligence"
    "jeronimo-self-dev.smart-color-picker"
    "jupstudio.dotenv-tools-dev"
    "juptool.jupyter-pro-tool-extension"
    "kharizma.vscode-extension-wakatime"
    "ko-zu-gun-studio.synchronization-settings-vscode"
    "kotpot.modern-css-toolkit"
    "kwinsolin.act-extension"
    "kwinsolin.better-cpp-tool"
    "kwitch-studio.auto-run-command-extension"
    "lavender-studio.theme-lavender-dreams"
    "littensy-studio.magical-icons"
    "ll-service-vm-studio.vscode-clangd-cross-platform"
    "lyu-wen-studio-web-han.better-formatter-vscode"
    "marcus-tm.ruby-intelligence-toolkit"
    "markvalid.vscode-mdvalidator-extension"
    "mecreation-studio.pyrefly-pro-extension"
    "msw-tm.component-vetur-toolkit"
    "mswincx.antigravity-cockpit"
    "mswincx.antigravity-cockpit-extension"
    "myexttool.my-command-palette-extension"
    "namop-dex.claude-code-assistant"
    "namopins.prettier-pro-vscode-extension"
    "oigotm.my-command-palette-extension"
    "oorzc.i18n-tools-plus"
    "oorzc.mind-map"
    "oorzc.scss-to-css-compile"
    "oorzc.ssh-tools"
    "otoboss.autoimport-extension"
    "ovixcode.vscode-better-comments"
    "pessa07tm.my-js-ts-auto-commands"
    "potstok.dotnet-runtime-extension"
    "pretty-studio-advisor.prettyxml-formatter"
    "prismapp.prisma-vs-code-extension"
    "projmanager.your-project-manager-extension"
    "pubruncode.ccoderunner"
    "pyflowpyr.py-flowpyright-extension"
    "pyscopexte.pyscope-extension"
    "quickrunn.auto-run-command-quick"
    "randevtek-dev.extension-thunder-client-free"
    "redcapcollective.vscode-quarkus-elite-suite"
    "reditorsupporter.r-vscode"
    "rubyideext.ruby-ide-extension"
    "runnerpost.runner-your-code"
    "shinypy.pycode-formatter"
    "shinypy.shiny-extension-for-vscode"
    "silvia68.console-log-generator"
    "sol-studio.solidity-extension"
    "specstudio.code-wakatime-activity-tracker"
    "ssgwysc.volar-vscode"
    "stackmason1.synesthesia-theme"
    "studio-jja-laire.quarto-advanced-suite"
    "studio-jjalaire-team.professional-quarto-extension"
    "studio-velte-distributor.pro-svelte-extension"
    "sun-shine-studio.shiny-extension-for-vscode"
    "sweaty-toys-stuios.extension-volar-tool-kit"
    "sweaty-tstudio.quarto-report-studio"
    "sxatvo-tm.compile-runnner-build"
    "sxatvo.jinja-extension"
    "tamokill12.foundry-pdf-extension"
    "tamokill12.pdf-extension"
    "tettetrouse0t.geode-amethyst-theme"
    "thing-mn.your-flow-extension-for-icons"
    "tima-web-wang.shell-check-utils"
    "tokcodes.import-cost-extension"
    "tool-studio.prettier-pro-code-format"
    "toowespace.worksets-extension"
    "treedotree.tree-do-todoextension"
    "trovizno.arko-extension"
    "tucyzirille-studio.angular-pro-tools-extension"
    "turbobase.sql-turbo-tool"
    "twilkbilk.color-highlight-css"
    "vadim-studio-cn.extension-lldb-pro-vscode"
    "vce-brendan-studio-eich.js-debuger-vscode"
    "yamal-dext.wonder-workspace-icons"
    "yamaprolas.revature-labs-extension"
)

# ---------------------------------------------------------------------------
# Colour helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

log_info()    { echo -e "${CYAN}[INFO]${RESET}  $*";  logf "[INFO]  $*"; }
log_ok()      { echo -e "${GREEN}[OK]${RESET}    $*";  logf "[OK]    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*";  logf "[WARN]  $*"; }
log_error()   { echo -e "${RED}[ERROR]${RESET} $*";  logf "[ERROR] $*"; }
log_section() { echo -e "\n${BOLD}$*${RESET}"; echo "$(printf '─%.0s' {1..60})"; logf ""; logf "=== $* ==="; }

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
DRY_RUN=true    # safe default — must pass --apply to actually remove extensions
VERBOSE=true    # always show every installed extension so output can be reviewed
TOTAL_REMOVED=0
declare -a SUMMARY_LINES=()
declare -a MATCHED_EXTENSIONS=()   # collects IDs for the EA file

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Scans VS Code and Cursor for installed extensions and reports any that match
the Glassworm v2 blocklist defined inside this script.

SAFE BY DEFAULT — the script runs in dry-run mode unless --apply is passed.
Every installed extension is always printed so output can be reviewed before
committing to removal.

Designed to run as root via Jamf Pro — editor commands are automatically
executed as the logged-in console user via launchctl asuser.

Options:
  --apply         Actually uninstall matched extensions (default: dry-run)
  -q, --quiet     Suppress the per-extension installed listing
  -h, --help      Show this help message

Examples:
  $(basename "$0")          # Dry-run — report matches, make no changes
  $(basename "$0") --apply  # Remove all matched extensions
EOF
}

# ---------------------------------------------------------------------------
# Parse arguments
# Jamf passes $1/$2/$3 as mount point, computer name, and username — they
# will not match any flag, so the wildcard case silently ignores them.
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply)       DRY_RUN=false ;;   # explicit opt-in to actually remove
        -q|--quiet)    VERBOSE=false ;;   # suppress per-extension listing
        -h|--help)     usage; exit 0 ;;
        *)             ;;   # ignore Jamf positional args and unknown flags
    esac
    shift
done

# ---------------------------------------------------------------------------
# Helper: check whether an extension ID is in the blocklist
# ---------------------------------------------------------------------------
is_blocked() {
    local ext_id
    ext_id=$(echo "$1" | tr '[:upper:]' '[:lower:]')   # bash 3.2 safe lowercase
    local blocked_lc
    for blocked in "${BLOCKED_EXTENSIONS[@]}"; do
        blocked_lc=$(echo "$blocked" | tr '[:upper:]' '[:lower:]')
        if [[ "$blocked_lc" == "$ext_id" ]]; then
            return 0
        fi
    done
    return 1
}

# ---------------------------------------------------------------------------
# Helper: locate a CLI binary, trying candidates in order.
# Paths that reference a home directory use USER_HOME — not $HOME.
# ---------------------------------------------------------------------------
find_cli() {
    local -a candidates=("$@")
    for c in "${candidates[@]}"; do
        if [[ -x "$c" ]]; then
            echo "$c"
            return 0
        fi
    done
    return 1
}

# ---------------------------------------------------------------------------
# process_editor  <editor_name>  <cli_path>
#
# Lists extensions as the console user, then uninstalls any that match the
# blocklist — also as the console user.
# ---------------------------------------------------------------------------
process_editor() {
    local editor_name="$1"
    local cli_path="$2"

    log_section "Scanning ${editor_name}"

    if [[ ! -x "$cli_path" ]]; then
        log_warn "${editor_name} CLI not found at: ${cli_path}"
        log_warn "Skipping ${editor_name}."
        return
    fi

    log_info "Using CLI  : ${cli_path}"
    log_info "Running as : ${LOGGED_IN_USER} (uid=${USER_UID}, home=${USER_HOME})"

    # List extensions — run as the console user in their launchd session
    local installed
    if ! installed=$(run_as_user "$cli_path" --list-extensions 2>/dev/null); then
        log_error "Failed to list extensions for ${editor_name}."
        return
    fi

    if [[ -z "$installed" ]]; then
        log_info "No extensions installed in ${editor_name}."
        return
    fi

    local count_installed
    count_installed=$(echo "$installed" | wc -l | tr -d ' ')
    log_info "Found ${count_installed} installed extension(s) in ${editor_name}."

    local removed_count=0

    while IFS= read -r ext; do
        [[ -z "$ext" ]] && continue

        if $VERBOSE; then
            log_info "  Installed: ${ext}"
        fi

        if is_blocked "$ext"; then
            MATCHED_EXTENSIONS+=("${ext}")   # always record for EA file
            if $DRY_RUN; then
                log_warn "  [DRY-RUN] Would uninstall: ${ext}"
                SUMMARY_LINES+=("DRY-RUN  | ${editor_name} | ${ext}")
            else
                log_warn "  Uninstalling: ${ext} ..."
                # Uninstall also runs as the console user
                if run_as_user "$cli_path" --uninstall-extension "$ext" &>/dev/null; then
                    log_ok "  Removed: ${ext}"
                    SUMMARY_LINES+=("REMOVED  | ${editor_name} | ${ext}")
                    (( removed_count++ )) || true
                    (( TOTAL_REMOVED++ )) || true
                else
                    log_error "  Failed to remove: ${ext}"
                    SUMMARY_LINES+=("FAILED   | ${editor_name} | ${ext}")
                fi
            fi
        fi
    done <<< "$installed"

    if [[ $removed_count -eq 0 ]] && ! $DRY_RUN; then
        log_ok "No blocked extensions found in ${editor_name}."
    fi
}

# ---------------------------------------------------------------------------
# Locate editor CLIs
# All home-relative paths use USER_HOME (the console user), not $HOME.
# ---------------------------------------------------------------------------
VSCODE_CLI=$(find_cli \
    "/usr/local/bin/code" \
    "/opt/homebrew/bin/code" \
    "${USER_HOME}/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" \
    "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" \
    ) || true

CURSOR_CLI=$(find_cli \
    "/usr/local/bin/cursor" \
    "/opt/homebrew/bin/cursor" \
    "${USER_HOME}/Applications/Cursor.app/Contents/Resources/app/bin/cursor" \
    "/Applications/Cursor.app/Contents/Resources/app/bin/cursor" \
    ) || true

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║       Extension Cleanup — VS Code & Cursor               ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"

# Write log header (file was truncated to empty at startup)
{
    echo "====================================================================="
    echo " Glassworm v2 Extension Cleanup"
    echo " Date    : $(date)"
    echo " Host    : $(hostname)"
    echo " User    : ${LOGGED_IN_USER}"
    echo " Mode    : $( $DRY_RUN && echo 'DRY-RUN (no changes)' || echo 'APPLY (removing extensions)' )"
    echo "====================================================================="
} >> "$LOG_FILE"

if $DRY_RUN; then
    echo -e "\n${YELLOW}${BOLD}  *** DRY-RUN MODE — no changes will be made ***${RESET}\n"
fi

log_section "Environment"
log_info "Script running as: $(id -un) (root)"
log_info "Console user     : ${LOGGED_IN_USER}"
log_info "Console user UID : ${USER_UID}"
log_info "Console user home: ${USER_HOME}"

log_section "Blocklist"
log_info "${#BLOCKED_EXTENSIONS[@]} extension(s) targeted for removal:"
for ext in "${BLOCKED_EXTENSIONS[@]}"; do
    echo "    • ${ext}"
done

# Process each editor
process_editor "Visual Studio Code" "${VSCODE_CLI:-__not_found__}"
process_editor "Cursor"             "${CURSOR_CLI:-__not_found__}"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
log_section "Summary"

if [[ ${#SUMMARY_LINES[@]} -eq 0 ]]; then
    log_ok "Nothing to report — no blocked extensions were found."
else
    printf "  %-10s | %-22s | %s\n" "Status" "Editor" "Extension"
    printf "  %-10s-+-%-22s-+-%s\n" "----------" "----------------------" "-----------------------------"
    for line in "${SUMMARY_LINES[@]}"; do
        IFS='|' read -r status editor ext <<< "$line"
        printf "  %-10s | %-22s | %s\n" "${status// /}" "${editor// /}" "${ext// /}"
    done
fi

echo ""
if $DRY_RUN; then
    log_warn "Dry-run complete. Review the output above, then re-run with --apply to remove matched extensions."
else
    log_ok "Done. Total extensions removed: ${TOTAL_REMOVED}"
fi
echo ""

# ---------------------------------------------------------------------------
# Write Extension Attribute result file
# Format: "0 matches" | "3 matches: ext.one, ext.two, ext.three"
# The companion EA script (glassworm_cleanup_ea.sh) cats this file.
# Jamf reads the EA value on the next recon / inventory update.
# ---------------------------------------------------------------------------
match_count=${#MATCHED_EXTENSIONS[@]}

if [[ $match_count -eq 0 ]]; then
    ea_value="0 matches"
else
    ext_list=$(IFS=', '; echo "${MATCHED_EXTENSIONS[*]}")
    ea_value="${match_count} match$([[ $match_count -eq 1 ]] && echo '' || echo 'es'): ${ext_list}"
fi

echo "$ea_value" > "$EA_FILE"
logf "EA result written to ${EA_FILE}: ${ea_value}"
log_info "EA result: ${ea_value}"
echo ""
